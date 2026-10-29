#!/usr/bin/env python3
"""Uji retry RPC nyata dalam database sementara (dibuat/dihapus oleh tes).

DATABASE_URL harus akun PostgreSQL staging/CI dengan izin CREATE DATABASE.
Tidak memakai password operator atau mengubah database bisnis yang ada.
"""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import threading
import unittest
from urllib.parse import urlsplit, urlunsplit
import uuid

ROOT = Path(__file__).resolve().parents[2]
_NO_KEY = object()


def quoted(value):
    return "null" if value is None else "'" + str(value).replace("'", "''") + "'"


class MutationRetryTest(unittest.TestCase):
    @classmethod
    def sql(cls, query, *, operator=False, role="authenticated", db=None):
        if operator:
            query = (f"set role {role}; set request.jwt.claims = "
                     "'{\"email\":\"retry@example.invalid\"}'; " + query)
        result = subprocess.run(
            [os.environ.get("PSQL", "psql"), "-XqAt", "-v", "ON_ERROR_STOP=1",
             "--dbname", db or cls.db, "-c", query],
            capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stderr.replace(cls.admin, "<DB_URL>"))
        return result.stdout.strip()

    @classmethod
    def setUpClass(cls):
        cls.admin = os.environ["DATABASE_URL"]
        name = "retry_test_" + uuid.uuid4().hex
        parts = urlsplit(cls.admin)
        cls.db = urlunsplit(parts._replace(path="/" + name))
        cls.sql(f'create database "{name}"', db=cls.admin)
        cls.addClassCleanup(lambda: cls.sql(f'drop database "{name}"', db=cls.admin))
        for path in [ROOT / "tests/integration/supabase_stub.sql",
                     *sorted((ROOT / "supabase/migrations").glob("*.sql"))]:
            cls.sql(path.read_text())
        cls.sql("""insert into business_settings(id,name,operator_email)
                   values(1,'Retry QA','retry@example.invalid');""")

    def setUp(self):
        suffix = uuid.uuid4().hex
        self.suffix = suffix
        self.sale = int(self.sql(f"""insert into sales
            (receipt_no,subtotal,total,idempotency_key)
            values('{suffix}',10000,10000,'{suffix}') returning id"""))
        self.ingredient = int(self.sql(f"""insert into ingredients(name,base_unit,balance)
            values('Retry {suffix}','pcs',100) returning id"""))
        # Fixture produksi batch: produk BATCH + resep aktif 10 pcs per porsi.
        self.product = int(self.sql(f"""insert into products(name,price,stock_mode)
            values('Batch {suffix}',5000,'BATCH') returning id"""))
        self.recipe = int(self.sql(f"""insert into recipe_versions
            (product_id,version,yield_qty,is_active)
            values({self.product},1,1,true) returning id"""))
        self.sql(f"""insert into recipe_items(recipe_version_id,ingredient_id,qty)
            values({self.recipe},{self.ingredient},10)""")

    def call(self, operation, key, *, amount=100, reason="retry QA", source="ADJUSTMENT",
             target=None, unit=None, operator=True, role="authenticated"):
        if operation == "refund":
            expression = (f"pos_refund({target or self.sale},{amount},"
                          f"{quoted(reason)},{quoted(key)})")
        else:
            expression = (f"inv_adjust_stock({target or self.ingredient},{amount},{quoted(unit)},"
                          f"{quoted(reason)},{quoted(source)},{quoted(key)})")
        return json.loads(self.sql("select " + expression,
                                   operator=operator, role=role))

    def totals(self):
        return json.loads(self.sql(f"""select jsonb_build_object(
            'refund',(select refund_amount from sales where id={self.sale}),
            'refund_rows',(select count(*) from refunds where sale_id={self.sale}),
            'balance',(select balance from ingredients where id={self.ingredient}),
            'movements',(select count(*) from stock_movements where ingredient_id={self.ingredient}),
            'refund_audit',(select count(*) from audit_events where entity='sale'
                and entity_id='{self.sale}' and action='REFUND'),
            'stock_audit',(select count(*) from audit_events where entity='ingredient'
                and entity_id='{self.ingredient}' and action in ('ADJUSTMENT','WASTE')))
            """))

    # ---- utilitas untuk mutasi hasil audit K06-01 (0014) ----

    @staticmethod
    def jsonb(value):
        return "'" + json.dumps(value).replace("'", "''") + "'::jsonb"

    def call_fn(self, name, literals, key=_NO_KEY, *, operator=True,
                role="authenticated"):
        args = list(literals)
        if key is not _NO_KEY:
            args.append(quoted(key))
        return json.loads(self.sql(f"select public.{name}({','.join(args)})",
                                   operator=operator, role=role))

    def purchase_args(self, supplier, status="RECEIVED", qty=1, price=1000):
        items = self.jsonb([{"ingredient_id": self.ingredient, "qty": qty,
                             "unit": "pcs", "total_price": price}])
        return [quoted(supplier), items, "'2026-10-27'", quoted(status)]

    def produce_args(self, qty=1, note="retry QA"):
        return [str(self.product), str(qty), quoted(note)]

    def expense_args(self, description, amount=1000, expense_id=None):
        return [quoted(expense_id), quoted("LISTRIK"), quoted(description),
                str(amount), quoted("ACTUAL"), "'2026-10-27'", "null"]

    def energy_args(self, note, watt=1000, hours=5):
        return [quoted("ELECTRICITY"), str(watt), str(hours), "80", "1444.7",
                "null", "null", "null", "4", quoted(note)]

    def counts(self):
        return json.loads(self.sql("""select jsonb_build_object(
            'purchases',(select count(*) from purchases),
            'purchase_moves',(select count(*) from stock_movements where source='PURCHASE'),
            'batches',(select count(*) from production_batches),
            'production_moves',(select count(*) from stock_movements where source='PRODUCTION'),
            'expenses',(select count(*) from expenses),
            'estimates',(select count(*) from energy_estimates),
            'purchase_audit',(select count(*) from audit_events where entity='purchase'),
            'energy_audit',(select count(*) from audit_events where entity='energy_estimate'))
            """))

    def delta(self, before):
        after = self.counts()
        return {k: after[k] - before[k] for k in after}

    def test_replay_lost_response_uses_original_result(self):
        for operation in ["refund", "stock"]:
            with self.subTest(operation=operation):
                key = uuid.uuid4().hex
                first = self.call(operation, key, amount=1)
                self.call(operation, uuid.uuid4().hex, amount=1)
                # Respons pertama hilang: koneksi baru mengulang key lama.
                replay = self.call(operation, key, amount=1)
                self.assertFalse(first.pop("idempotent_replay"))
                self.assertTrue(replay.pop("idempotent_replay"))
                self.assertEqual(first, replay)
        self.assertEqual(self.totals(), dict(refund=2, refund_rows=2, balance=102,
                                            movements=2, refund_audit=2, stock_audit=2))

    def test_concurrent_same_key_commits_once(self):
        for operation in ["refund", "stock"]:
            key, barrier = uuid.uuid4().hex, threading.Barrier(8)

            def send(_):
                barrier.wait(timeout=10)
                return self.call(operation, key, amount=1)

            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(send, range(8)))
            self.assertEqual(sum(not r["idempotent_replay"] for r in results), 1)
        self.assertEqual(self.totals(), dict(refund=1, refund_rows=1, balance=101,
                                            movements=1, refund_audit=1, stock_audit=1))

    def test_payload_conflicts_and_target_changes_are_rejected(self):
        for operation in ["refund", "stock"]:
            key = uuid.uuid4().hex
            self.call(operation, key, amount=1)
            for changed in [dict(amount=2), dict(reason="different reason"), dict(target=999999)]:
                with self.subTest(operation=operation, changed=changed):
                    with self.assertRaisesRegex(AssertionError, "idempotency_key_conflict"):
                        self.call(operation, key, **dict(dict(amount=1), **changed))
        self.assertEqual(self.totals()["refund_rows"], 1)
        self.assertEqual(self.totals()["movements"], 1)

    def test_concurrent_distinct_operations_are_not_deduplicated(self):
        for operation in ["refund", "stock"]:
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(lambda _: self.call(
                    operation, uuid.uuid4().hex, amount=1), range(8)))
            self.assertTrue(all(not row["idempotent_replay"] for row in results))
        self.assertEqual(self.totals()["refund"], 8)
        self.assertEqual(self.totals()["refund_rows"], 8)
        self.assertEqual(self.totals()["balance"], 108)
        self.assertEqual(self.totals()["movements"], 8)

    def test_waste_and_negative_adjustment_replay(self):
        for source, amount in [("WASTE", 2), ("ADJUSTMENT", -3)]:
            key = uuid.uuid4().hex
            self.call("stock", key, amount=amount, source=source)
            self.assertTrue(self.call("stock", key, amount=amount,
                                      source=source)["idempotent_replay"])
        self.assertEqual(self.totals()["balance"], 95)
        self.assertEqual(self.totals()["movements"], 2)

    def test_unit_conversion_validation_and_unit_conflict(self):
        self.sql(f"update ingredients set base_unit='g' where id={self.ingredient}")
        key = uuid.uuid4().hex
        self.call("stock", key, amount=2, unit="kg")
        self.call("stock", key, amount=2, unit="kg")
        self.assertEqual(self.totals()["balance"], 2100)
        with self.assertRaisesRegex(AssertionError, "idempotency_key_conflict"):
            self.call("stock", key, amount=2, unit="g")
        with self.assertRaises(AssertionError):
            self.call("stock", uuid.uuid4().hex, amount=2, unit="pcs")
        with self.assertRaisesRegex(AssertionError, "invalid_qty"):
            self.call("stock", uuid.uuid4().hex, amount=-2, source="WASTE")
        self.assertEqual(self.totals()["movements"], 1)

    def test_missing_bad_keys_fail_without_side_effects(self):
        for operation in ["refund", "stock"]:
            for key in [None, "", "       ", "short", "x" * 129]:
                with self.subTest(operation=operation, key=key):
                    with self.assertRaisesRegex(AssertionError, "missing_idempotency_key"):
                        self.call(operation, key)
        self.assertEqual(self.totals()["refund_rows"], 0)
        self.assertEqual(self.totals()["movements"], 0)

    def test_failed_and_rolled_back_attempts_do_not_reserve_key(self):
        for operation in ["refund", "stock"]:
            key = uuid.uuid4().hex
            with self.assertRaises(AssertionError):
                self.call(operation, key, amount=20000 if operation == "refund" else 0)
            self.assertFalse(self.call(operation, key, amount=1)["idempotent_replay"])
        key = uuid.uuid4().hex
        self.sql(f"begin; set local request.jwt.claims = "
                 "'{\"email\":\"retry@example.invalid\"}'; "
                 f"select pos_refund({self.sale},1,'rollback QA','{key}'); rollback;")
        self.assertFalse(self.call("refund", key, amount=1, reason="rollback QA")["idempotent_replay"])
        self.assertEqual(self.totals()["refund"], 2)

    def test_authorization_and_legacy_bypass_are_closed(self):
        for operation in ["refund", "stock"]:
            key = uuid.uuid4().hex
            self.call(operation, key, amount=1)
            with self.assertRaisesRegex(AssertionError, "permission denied"):
                self.call(operation, key, amount=1, role="anon")
            with self.assertRaisesRegex(AssertionError, "operator_required"):
                self.sql("set role authenticated; set request.jwt.claims = "
                         "'{\"email\":\"other@example.invalid\"}'; "
                         + (f"select pos_refund({self.sale},1,'retry QA','{key}')"
                            if operation == "refund" else
                            f"select inv_adjust_stock({self.ingredient},1,null,'retry QA','ADJUSTMENT','{key}')"))
        for statement in [f"select pos_refund_once({self.sale},1,'bypass QA')",
                          f"select inv_adjust_stock_once({self.ingredient},1,null,'bypass QA','ADJUSTMENT')",
                          "select * from mutation_requests"]:
            with self.assertRaisesRegex(AssertionError, "permission denied"):
                self.sql(statement, operator=True)
        for statement in [f"select pos_refund({self.sale},1,'legacy QA')",
                          f"select inv_adjust_stock({self.ingredient},1,null,'legacy QA','ADJUSTMENT')"]:
            with self.assertRaisesRegex(AssertionError, "missing_idempotency_key"):
                self.sql(statement, operator=True)


    # ---- Audit K06-01 (migrasi 0014): mutasi yang dulu menggandakan efek ----

    def new_mutation_cases(self):
        return [
            ("inv_create_purchase", self.purchase_args("Supplier QA")),
            ("inv_produce_batch", self.produce_args()),
            ("exp_save", self.expense_args(f"Biaya {self.suffix}")),
            ("energy_save_estimate", self.energy_args(f"Energi {self.suffix}")),
        ]

    def test_new_mutations_replay_uses_original_result(self):
        before = self.counts()
        for name, args in self.new_mutation_cases():
            with self.subTest(name=name):
                key = uuid.uuid4().hex
                first = self.call_fn(name, args, key)
                self.call_fn(name, args, uuid.uuid4().hex)
                # Respons pertama hilang: koneksi baru mengulang key lama.
                replay = self.call_fn(name, args, key)
                self.assertFalse(first.pop("idempotent_replay"))
                self.assertTrue(replay.pop("idempotent_replay"))
                self.assertEqual(first, replay)
        self.assertEqual(self.delta(before), dict(
            purchases=2, purchase_moves=2, batches=2, production_moves=2,
            expenses=4, estimates=2, purchase_audit=2, energy_audit=2))
        self.assertEqual(self.totals()["balance"], 82)

    def test_new_mutations_concurrent_same_key_commits_once(self):
        before = self.counts()
        for name, args in self.new_mutation_cases():
            key, barrier = uuid.uuid4().hex, threading.Barrier(8)

            def send(_):
                barrier.wait(timeout=10)
                return self.call_fn(name, args, key)

            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(send, range(8)))
            self.assertEqual(sum(not r["idempotent_replay"] for r in results), 1,
                             name)
        self.assertEqual(self.delta(before), dict(
            purchases=1, purchase_moves=1, batches=1, production_moves=1,
            expenses=2, estimates=1, purchase_audit=1, energy_audit=1))
        self.assertEqual(self.totals()["balance"], 91)

    def test_new_mutations_payload_conflict_is_rejected(self):
        changed = {
            "inv_create_purchase": self.purchase_args("Supplier QA",
                                                      status="ORDERED"),
            "inv_produce_batch": self.produce_args(qty=2),
            "exp_save": self.expense_args(f"Biaya {self.suffix}", amount=2000),
            "energy_save_estimate": self.energy_args(f"Energi {self.suffix}",
                                                     watt=2000),
        }
        before = self.counts()
        for name, args in self.new_mutation_cases():
            with self.subTest(name=name):
                key = uuid.uuid4().hex
                self.call_fn(name, args, key)
                with self.assertRaisesRegex(AssertionError,
                                            "idempotency_key_conflict"):
                    self.call_fn(name, changed[name], key)
        self.assertEqual(self.delta(before), dict(
            purchases=1, purchase_moves=1, batches=1, production_moves=1,
            expenses=2, estimates=1, purchase_audit=1, energy_audit=1))

    def test_new_mutations_missing_key_and_legacy_path_closed(self):
        before = self.counts()
        cases = self.new_mutation_cases()
        for name, args in cases:
            with self.subTest(name=name, key="absent"):
                with self.assertRaisesRegex(AssertionError,
                                            "missing_idempotency_key"):
                    self.call_fn(name, args)
            for bad in ["", "       ", "short", "x" * 129]:
                with self.subTest(name=name, key=bad):
                    with self.assertRaisesRegex(AssertionError,
                                                "missing_idempotency_key"):
                        self.call_fn(name, args, bad)
        for statement in [
            f"select public.inv_create_purchase_once('Legacy {self.suffix}',"
            f" '[{{\"ingredient_id\": {self.ingredient}, \"qty\": 1, "
            f"\"unit\": \"pcs\", \"total_price\": 1}}]'::jsonb, "
            "'2026-10-27', 'RECEIVED')",
            f"select public.inv_produce_batch_once({self.product},1,'legacy')",
            f"select public.exp_save_once(null,'LISTRIK','legacy expense',1000,"
            "'ACTUAL','2026-10-27',null)",
            "select public.energy_save_estimate_once('ELECTRICITY',1000,5,80,"
            "1444.7,null,null,null,4,'legacy')",
            "select public.mutation_run_once('exp_save','legacykey01','{}','x')",
            "select * from mutation_requests",
        ]:
            with self.subTest(statement=statement[:40]):
                with self.assertRaisesRegex(AssertionError,
                                            "permission denied"):
                    self.sql(statement, operator=True)
        for name, args in cases:
            with self.subTest(name=name, role="anon"):
                with self.assertRaisesRegex(AssertionError,
                                            "permission denied"):
                    self.call_fn(name, args, uuid.uuid4().hex, role="anon")
            with self.subTest(name=name, role="non-operator"):
                with self.assertRaisesRegex(AssertionError,
                                            "operator_required"):
                    self.sql("set role authenticated; set request.jwt.claims = "
                             "'{\"email\":\"other@example.invalid\"}'; "
                             f"select public.{name}({','.join(list(args) + [quoted(uuid.uuid4().hex)])})")
        self.assertEqual(self.delta(before), dict(
            purchases=0, purchase_moves=0, batches=0, production_moves=0,
            expenses=0, estimates=0, purchase_audit=0, energy_audit=0))

    def test_expense_update_path_is_repeatable_without_key(self):
        before = self.counts()
        created = self.call_fn("exp_save",
                               self.expense_args(f"Biaya {self.suffix}"),
                               uuid.uuid4().hex)
        args = self.expense_args(f"Biaya {self.suffix} revisi", amount=2000,
                                 expense_id=created["id"])
        first = self.call_fn("exp_save", args)
        second = self.call_fn("exp_save", args)
        self.assertEqual(first, second)
        self.assertEqual(first["amount"], 2000)
        with self.assertRaisesRegex(AssertionError, "operator_required"):
            self.sql("set role authenticated; set request.jwt.claims = "
                     "'{\"email\":\"other@example.invalid\"}'; "
                     f"select public.exp_save({','.join(args)})")
        # Jalur update tidak menempati cache retry (tidak mengunci edit berikutnya).
        self.assertEqual(int(self.sql(
            "select count(*) from mutation_requests where operation='exp_save'")), 1)
        self.assertEqual(self.delta(before), dict(
            purchases=0, purchase_moves=0, batches=0, production_moves=0,
            expenses=1, estimates=0, purchase_audit=0, energy_audit=0))

    def test_new_mutation_rollback_does_not_reserve_key(self):
        key = uuid.uuid4().hex
        before = self.counts()
        self.sql(f"begin; set local request.jwt.claims = "
                 "'{\"email\":\"retry@example.invalid\"}'; "
                 f"select public.inv_create_purchase('Rollback {self.suffix}',"
                 f"{self.purchase_args('Rollback')[1]}, '2026-10-27',"
                 f"'RECEIVED','{key}'); rollback;")
        result = self.call_fn("inv_create_purchase",
                              self.purchase_args(f"Rollback {self.suffix}"), key)
        self.assertFalse(result["idempotent_replay"])
        self.assertEqual(self.delta(before)["purchases"], 1)

    # ---- Audit 0015: guard is_operator() seragam pada semua RPC klien ----

    CLIENT_RPCS = [
        "select public.pos_quote('[]'::jsonb)",
        "select public.pos_checkout('[]'::jsonb,'CASH',0)",
        "select public.pos_sale_receipt(1)",
        "select public.pos_dashboard_summary()",
        "select public.qr_list_drafts()",
        "select public.qr_claim_draft(1)",
        "select public.qr_cancel_draft(1)",
        "select public.qr_complete_draft(1,1)",
        "select public.qr_create_table('Guard QA')",
        "select public.qr_rotate_token(1)",
        "select public.inv_save_ingredient(null,'Guard','g',1,1)",
        "select public.inv_receive_purchase(1)",
        "select public.inv_save_recipe(1,1,'[]'::jsonb)",
        "select public.inv_hpp(1)",
        "select public.cost_allocate(1,'guard',1)",
        "select public.cash_shift_status()",
        "select public.cash_shift_open(0)",
        "select public.cash_shift_close(0,null)",
        "select public.pos_reports()",
    ]

    INTERNAL_HELPERS = [
        "select public.pos_line_total(1,1,'[]'::jsonb)",
        "select public.qr_draft_json(1)",
        "select public.hash_table_token('x')",
    ]

    def test_non_operator_authenticated_is_rejected_by_every_client_rpc(self):
        """RPC lama (Sprint 02-05) kini menolak akun non-operator (0015).

        Fungsi SECURITY DEFINER melewati RLS; tanpa guard ini akun
        authenticated kedua bisa memanggil pos_checkout/dsb via PostgREST.
        """
        intruder = ("set role authenticated; set request.jwt.claims = "
                    "'{\"email\":\"other@example.invalid\"}'; ")
        for statement in self.CLIENT_RPCS:
            with self.subTest(statement=statement[:45]):
                with self.assertRaisesRegex(AssertionError,
                                            "operator_required"):
                    self.sql(intruder + statement)

    def test_client_rpcs_remain_closed_to_anon(self):
        for statement in self.CLIENT_RPCS:
            with self.subTest(statement=statement[:45]):
                with self.assertRaisesRegex(AssertionError,
                                            "permission denied"):
                    self.sql("set role anon; " + statement)

    def test_internal_helpers_are_closed_even_to_operator(self):
        """pos_line_total/qr_draft_json/hash_table_token hanya untuk definer."""
        for statement in self.INTERNAL_HELPERS:
            with self.subTest(statement=statement[:45]):
                with self.assertRaisesRegex(AssertionError,
                                            "permission denied"):
                    self.sql(statement, operator=True)

    def test_operator_calls_and_public_qr_path_survive_the_guard(self):
        self.assertTrue(
            self.sql("select public.pos_dashboard_summary()",
                     operator=True).startswith("{"))
        self.assertTrue(
            self.sql("select public.qr_list_drafts()",
                     operator=True).startswith("["))
        # Jalur anon publik (menu + submit draft) tidak terpengaruh 0015.
        token = "guard-qa-token-01"
        self.sql(f"""insert into dining_tables(label, qr_token_hash)
                     values('Guard QA', public.hash_table_token('{token}'))""")
        self.assertTrue(self.sql(f"select public.get_public_menu('{token}')",
                                 role="anon").startswith("{"))
        draft = json.loads(self.sql(
            f"select public.qr_submit_draft('{token}','guard-client-01',"
            f"'[{{\"product_id\": {self.product}, \"qty\": 1}}]'::jsonb)",
            role="anon"))
        self.assertEqual(draft["item_count"], 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)

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
        self.sale = int(self.sql(f"""insert into sales
            (receipt_no,subtotal,total,idempotency_key)
            values('{suffix}',10000,10000,'{suffix}') returning id"""))
        self.ingredient = int(self.sql(f"""insert into ingredients(name,base_unit,balance)
            values('Retry {suffix}','pcs',100) returning id"""))

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


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Uji pesanan manual (migrasi 0022) di database sementara.

DATABASE_URL harus akun PostgreSQL staging/CI dengan izin CREATE DATABASE.
Tidak memakai password operator atau mengubah database bisnis yang ada.
Pola sama dengan test_qr_tables.py: bikin DB sementara, terapkan stub + semua
migrasi, jalankan sebagai role authenticated dengan klaim operator.

Menguji qr_manual_order_create & qr_draft_add_items:

  T-01  buat pesanan manual: lahir CLAIMED (bukan PENDING), nama/wa tersimpan,
        subtotal = hitungan server (harga snapshot), item tersimpan lengkap
        (nama + harga snapshot + modifier + catatan).
  T-02  tambah item ("minta lagi"): subtotal & item_count DIHITUNG ULANG
        server dari seluruh baris — kiriman palsu (qty/harga tidak valid)
        tidak pernah mengubah total.
  T-03  draft selesai/dibatalkan/kedaluwarsa tidak bisa ditambah
        (draft_not_editable); PENDING (QR pelanggan) BISA ditambah.
  T-04  produk tidak aktif/arsip -> product_unavailable; modifier tidak
        terkait produk -> modifier_not_allowed; qty di luar 1..99 ->
        invalid_qty. Tidak ada baris item yang tertinggal (rollback loop
        kena exception -> seluruh fungsi gagal atomik).
  T-05  non-operator ditolak (operator_required); anon tanpa grant.
  T-06  input tidak valid: nama kosong -> invalid_customer_name; nama >60 ->
        invalid_customer_name; items kosong/bukan array -> invalid_items;
        meja tidak ada/nonaktif -> table_not_found.

Kejujuran uang: fungsi tidak pernah menulis sales — hanya draft; total final
tetap dari pos_checkout saat operator membayar.
"""
import json
import os
from pathlib import Path
import subprocess
import unittest
from urllib.parse import urlsplit, urlunsplit
import uuid

ROOT = Path(__file__).resolve().parents[2]


def q(value, sql_type=None):
    """Kutip literal SQL (string/number/bool/None/list/dict) dengan aman.

    sql_type: tipe eksplisit untuk panggilan argumen bernamed (mis. 'text')
    — Postgres tak bisa memilih overload dari literal string ('unknown').
    """
    if value is None:
        return "null"
    if isinstance(value, bool):
        lit = "true" if value else "false"
    elif isinstance(value, (int, float)):
        return str(value)
    elif isinstance(value, (list, dict)):
        lit = json.dumps(value).replace("'", "''")
    else:
        lit = str(value).replace("'", "''")
    return f"'{lit}'::{sql_type}" if sql_type else f"'{lit}'"


class ManualOrdersTest(unittest.TestCase):
    PARAM_TYPES = {
        "qr_manual_order_create": {
            "p_table_id": "bigint",
            "p_customer_name": "text",
            "p_customer_phone": "text",
            "p_items": "jsonb",
        },
        "qr_draft_add_items": {"p_draft_id": "bigint", "p_items": "jsonb"},
    }

    @classmethod
    def sql(cls, query, *, operator=False, role="authenticated", db=None):
        if operator:
            claims = json.dumps({"email": "manual@example.invalid"})
            query = (f"set role {role}; set request.jwt.claims = "
                     f"'{claims}'; " + query)
        result = subprocess.run(
            [os.environ.get("PSQL", "psql"), "-XqAt", "-v", "ON_ERROR_STOP=1",
             "--dbname", db or cls.db, "-c", query],
            capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stderr.replace(cls.admin, "<DB_URL>"))
        return result.stdout.strip()

    def rpc(self, fn, **params):
        types = self.PARAM_TYPES.get(fn, {})
        args = ", ".join(f"{k} => {q(v, types.get(k))}"
                         for k, v in params.items())
        out = self.sql(f"select public.{fn}({args})::text;", operator=True)
        return json.loads(out)

    @classmethod
    def setUpClass(cls):
        cls.admin = os.environ["DATABASE_URL"]
        name = "manual_test_" + uuid.uuid4().hex
        parts = urlsplit(cls.admin)
        cls.db = urlunsplit(parts._replace(path="/" + name))
        cls.sql(f'create database "{name}"', db=cls.admin)
        cls.addClassCleanup(
            lambda: cls.sql(f'drop database "{name}"', db=cls.admin))
        for path in [ROOT / "tests/integration/supabase_stub.sql",
                     *sorted((ROOT / "supabase/migrations").glob("*.sql"))]:
            cls.sql(path.read_text())
        cls.sql("""insert into business_settings(id,name,operator_email)
                   values(1,'Manual QA','manual@example.invalid');""")

    def setUp(self):
        self.suffix = uuid.uuid4().hex[:8].upper()
        # Meja aktif + meja nonaktif.
        self.table_id = int(self.sql(
            "insert into dining_tables(label, qr_token_hash) "
            f"values('MEJA-{self.suffix}', 'tok-{self.suffix}') "
            "returning id;"))
        self.disabled_table_id = int(self.sql(
            "insert into dining_tables(label, qr_token_hash, is_enabled) "
            f"values('MATI-{self.suffix}', 'tok-off-{self.suffix}', false) "
            "returning id;"))
        # Kategori + produk: satu aktif, satu arsip.
        cat = int(self.sql(
            "insert into product_categories(name) "
            f"values('Kat {self.suffix}') returning id;"))
        self.product_id = int(self.sql(
            "insert into products(name, price, category_id) "
            f"values('Nasi {self.suffix}', 10000, {cat}) "
            "returning id;"))
        self.archived_id = int(self.sql(
            "insert into products(name, price, category_id, archived_at) "
            f"values('Arsip {self.suffix}', 5000, {cat}, now()) "
            "returning id;"))
        # Modifier terkait produk aktif.
        mod = int(self.sql(
            "insert into modifiers(name, price_delta) "
            f"values('Pedas {self.suffix}', 2000) returning id;"))
        self.sql("insert into product_modifiers(product_id, modifier_id) "
                 f"values({self.product_id}, {mod});")
        self.mod_id = mod

    # ------------------------------------------------------------------
    # T-01: buat pesanan manual — lahir CLAIMED, snapshot harga server
    # ------------------------------------------------------------------
    def test_create_manual_order_flow(self):
        out = self.rpc(
            "qr_manual_order_create",
            p_table_id=self.table_id,
            p_customer_name=f"Budi {self.suffix}",
            p_customer_phone="6281234567",
            p_items=[
                {"product_id": self.product_id, "qty": 2,
                 "modifier_ids": [self.mod_id], "note": "tanpa sendok"},
            ],
        )
        self.assertEqual(out["status"], "CLAIMED",
                         "pesanan manual lahir langsung Diterima")
        self.assertEqual(out["customer_name"], f"Budi {self.suffix}")
        self.assertEqual(out["customer_phone"], "6281234567")
        self.assertEqual(out["table_label"], f"MEJA-{self.suffix}")
        # Snapshot server: (10000 + 2000) * 2, bukan harga kiriman klien.
        self.assertEqual(out["subtotal"], 24000)
        self.assertEqual(out["item_count"], 1)
        item = out["items"][0]
        self.assertEqual(item["product_name"], f"Nasi {self.suffix}")
        self.assertEqual(item["unit_price"], 12000)
        self.assertEqual(item["qty"], 2)
        self.assertEqual(item["note"], "tanpa sendok")
        self.assertEqual(item["modifiers"][0]["name"], f"Pedas {self.suffix}")

    # ------------------------------------------------------------------
    # T-02: tambah item — subtotal dihitung ulang server dari seluruh baris
    # ------------------------------------------------------------------
    def test_add_items_recomputes_subtotal(self):
        created = self.rpc(
            "qr_manual_order_create",
            p_table_id=self.table_id,
            p_customer_name=f"Sari {self.suffix}",
            p_items=[{"product_id": self.product_id, "qty": 1}],
        )
        draft_id = created["draft_id"]
        self.assertEqual(created["subtotal"], 10000)

        out = self.rpc(
            "qr_draft_add_items",
            p_draft_id=draft_id,
            p_items=[{"product_id": self.product_id, "qty": 3},
                     {"product_id": self.product_id, "qty": 1,
                      "modifier_ids": [self.mod_id]}],
        )
        # 3 baris: 10000 + 30000 + 12000 — dihitung ulang dari baris item.
        self.assertEqual(out["subtotal"], 52000)
        self.assertEqual(out["item_count"], 3)
        self.assertEqual(len(out["items"]), 3)
        # Draft tetap berstatus Diterima (tidak berputar status).
        self.assertEqual(out["status"], "CLAIMED")

    # ------------------------------------------------------------------
    # T-03: hanya draft AKTIF yang bisa ditambah; PENDING QR juga boleh
    # ------------------------------------------------------------------
    def test_add_items_blocks_terminal_allows_pending(self):
        created = self.rpc(
            "qr_manual_order_create",
            p_table_id=self.table_id,
            p_customer_name=f'Term {self.suffix}',
            p_items=[{"product_id": self.product_id, "qty": 1}])
        draft_id = created["draft_id"]

        # Draft QR PENDING (bukan buatan manual) — tetap boleh ditambah.
        pending_id = int(self.sql(
            "insert into qr_drafts(table_id, table_label, client_key) "
            f"values({self.table_id}, 'MEJA', 'qr-{self.suffix}') "
            "returning id;"))
        out = self.rpc("qr_draft_add_items", p_draft_id=pending_id,
                       p_items=[{"product_id": self.product_id, "qty": 1}])
        self.assertEqual(out["item_count"], 1)

        for status in ("COMPLETED", "CANCELLED", "EXPIRED"):
            with self.subTest(status=status):
                self.sql("update qr_drafts set status = %s where id = %s;"
                         % (q(status), draft_id))
                with self.assertRaisesRegex(AssertionError,
                                            "draft_not_editable"):
                    self.rpc("qr_draft_add_items", p_draft_id=draft_id,
                             p_items=[{"product_id": self.product_id,
                                       "qty": 1}])

    # ------------------------------------------------------------------
    # T-04: validasi pos_line_total dijalur manual — atomik, tanpa sisa
    # ------------------------------------------------------------------
    def test_invalid_product_and_modifier_rejected(self):
        # Produk diarsipkan -> ditolak; tidak ada draft setengah jadi.
        with self.assertRaisesRegex(AssertionError, "product_unavailable"):
            self.rpc("qr_manual_order_create", p_table_id=self.table_id,
                     p_customer_name=f"X {self.suffix}",
                     p_items=[{"product_id": self.archived_id, "qty": 1}])

        # Modifier tidak terkait produk -> ditolak.
        orphan = int(self.sql(
            "insert into modifiers(name, price_delta) "
            f"values('Orphan {self.suffix}', 1000) returning id;"))
        with self.assertRaisesRegex(AssertionError, "modifier_not_allowed"):
            self.rpc("qr_manual_order_create", p_table_id=self.table_id,
                     p_customer_name=f"X {self.suffix}",
                     p_items=[{"product_id": self.product_id, "qty": 1,
                               "modifier_ids": [orphan]}])

        # Qty di luar 1..99 -> invalid_qty.
        with self.assertRaisesRegex(AssertionError, "invalid_qty"):
            self.rpc("qr_draft_add_items",
                     p_draft_id=self._draft(),
                     p_items=[{"product_id": self.product_id, "qty": 0}])

        # Kebersihan: gagal total tidak meninggalkan draft buatan parsial.
        self.assertEqual(
            self.sql("select count(*) from qr_drafts d "
                     f"where d.customer_name = 'X {self.suffix}';"), "0")

    def _draft(self):
        return int(self.rpc(
            "qr_manual_order_create", p_table_id=self.table_id,
            p_customer_name=f"Y {self.suffix}",
            p_items=[{"product_id": self.product_id, "qty": 1}])["draft_id"])

    # ------------------------------------------------------------------
    # T-05: guard operator
    # ------------------------------------------------------------------
    def test_non_operator_rejected(self):
        args = (f"select public.qr_manual_order_create({self.table_id}, "
                "'X', null, '[{\"product_id\": 1, \"qty\": 1}]'::jsonb);")
        result = subprocess.run(
            [os.environ.get("PSQL", "psql"), "-XqAt", "-v",
             "ON_ERROR_STOP=1", "--dbname", self.db, "-c",
             "set role authenticated; set request.jwt.claims = '{}'; " + args],
            capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("operator_required", result.stderr)

        result = subprocess.run(
            [os.environ.get("PSQL", "psql"), "-XqAt", "-v",
             "ON_ERROR_STOP=1", "--dbname", self.db, "-c",
             "set role authenticated; set request.jwt.claims = '{}'; "
             "select public.qr_draft_add_items(1, "
             "'[{\"product_id\": 1, \"qty\": 1}]'::jsonb);"],
            capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("operator_required", result.stderr)

    # ------------------------------------------------------------------
    # T-06: input tidak valid
    # ------------------------------------------------------------------
    def test_invalid_inputs_rejected(self):
        with self.assertRaisesRegex(AssertionError, "invalid_customer_name"):
            self.rpc("qr_manual_order_create", p_table_id=self.table_id,
                     p_customer_name="   ",
                     p_items=[{"product_id": self.product_id, "qty": 1}])
        with self.assertRaisesRegex(AssertionError, "invalid_customer_name"):
            self.rpc("qr_manual_order_create", p_table_id=self.table_id,
                     p_customer_name="x" * 61,
                     p_items=[{"product_id": self.product_id, "qty": 1}])
        with self.assertRaisesRegex(AssertionError, "invalid_items"):
            self.rpc("qr_manual_order_create", p_table_id=self.table_id,
                     p_customer_name=f"Z {self.suffix}", p_items=[])
        with self.assertRaisesRegex(AssertionError, "table_not_found"):
            self.rpc("qr_manual_order_create", p_table_id=self.disabled_table_id,
                     p_customer_name=f"Z {self.suffix}",
                     p_items=[{"product_id": self.product_id, "qty": 1}])
        with self.assertRaisesRegex(AssertionError, "table_not_found"):
            self.rpc("qr_manual_order_create", p_table_id=999999999,
                     p_customer_name=f"Z {self.suffix}",
                     p_items=[{"product_id": self.product_id, "qty": 1}])


if __name__ == "__main__":
    unittest.main(verbosity=2)

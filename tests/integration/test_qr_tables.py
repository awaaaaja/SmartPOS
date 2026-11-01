#!/usr/bin/env python3
"""Uji fitur hapus meja (Meja & QR, migrasi 0021) di database sementara.

DATABASE_URL harus akun PostgreSQL staging/CI dengan izin CREATE DATABASE.
Tidak memakai password operator atau mengubah database bisnis yang ada.
Pola sama dengan test_mutation_retry.py: bikin DB sementara, terapkan stub +
semua migrasi, jalankan sebagai role authenticated dengan klaim operator.

Menguji qr_delete_table (S03 / rencana tambah-hapus meja):

  T-01  alur penuh: qr_create_table -> qr_rotate_token -> qr_delete_table
        (label unik, token berganti, meja hilang setelah dihapus).
  T-02  meja dengan pesanan AKTIF (PENDING) ditolak (table_has_active_orders);
        setelah draft jadi terminal (EXPIRED) penghapusan berhasil dan
        draft terminal ikut terhapus.
  T-03  riwayat penjualan TIDAK dihapus: baris sales tetap ada, hanya
        table_id dilepas (sales_detached); draft COMPLETED berbayar ikut
        terhapus (buku tiket, bukan buku uang).
  T-04  non-operator ditolak (operator_required / 42501).
  T-05  id tidak ada -> table_not_found.

Kejujuran uang: fungsi tidak pernah menghapus baris sales — hanya melepas
tautan meja; jumlah uang berubah nol.
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

    sql_type: tipe eksplisit untuk panggilan argumen bernama (mis. 'text')
    — Postgres tak bisa memilih overload dari literal string ('unknown').
    Angka literal dibiarkan (integer bawaan, koerse rapi ke numeric/bigint).
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


class TablesDeleteTest(unittest.TestCase):
    # Tipe parameter string dari definisi fungsi (lihat migrasi).
    PARAM_TYPES = {
        "qr_create_table": {"p_label": "text"},
        "qr_rotate_token": {"p_table_id": "bigint"},
        "qr_delete_table": {"p_table_id": "bigint"},
    }

    @classmethod
    def sql(cls, query, *, operator=False, role="authenticated", db=None):
        if operator:
            claims = json.dumps({"email": "tables@example.invalid"})
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
        # Argumen bernama + cast eksplisit (PARAM_TYPES); keluaran ::text
        # supaya pslq mencetak JSON ketat lalu di-parse.
        types = self.PARAM_TYPES.get(fn, {})
        args = ", ".join(f"{k} => {q(v, types.get(k))}"
                         for k, v in params.items())
        out = self.sql(f"select public.{fn}({args})::text;", operator=True)
        return json.loads(out)

    @classmethod
    def setUpClass(cls):
        cls.admin = os.environ["DATABASE_URL"]
        name = "tables_test_" + uuid.uuid4().hex
        parts = urlsplit(cls.admin)
        cls.db = urlunsplit(parts._replace(path="/" + name))
        cls.sql(f'create database "{name}"', db=cls.admin)
        cls.addClassCleanup(
            lambda: cls.sql(f'drop database "{name}"', db=cls.admin))
        for path in [ROOT / "tests/integration/supabase_stub.sql",
                     *sorted((ROOT / "supabase/migrations").glob("*.sql"))]:
            cls.sql(path.read_text())
        cls.sql("""insert into business_settings(id,name,operator_email)
                   values(1,'Tables QA','tables@example.invalid');""")

    def _create(self, label=None):
        label = label or ("QA-MEJA-" + uuid.uuid4().hex[:6].upper())
        row = self.rpc("qr_create_table", p_label=label)
        return int(row["table_id"]), row["token"], label

    # ------------------------------------------------------------------
    # T-01: alur penuh create -> rotate -> delete
    # ------------------------------------------------------------------
    def test_create_rotate_delete_flow(self):
        tid, token1, label = self._create()
        rotated = self.rpc("qr_rotate_token", p_table_id=tid)
        self.assertNotEqual(rotated["token"], token1,
                            "token harus berganti setelah rotasi")
        self.assertEqual(
            self.sql("select token_version from dining_tables "
                     f"where id = {tid};"), "2")

        out = self.rpc("qr_delete_table", p_table_id=tid)
        self.assertEqual(out["label"], label)
        self.assertEqual(out["drafts_removed"], 0)
        self.assertEqual(out["sales_detached"], 0)
        self.assertEqual(
            self.sql(f"select count(*) from dining_tables where id = {tid};"),
            "0")

    def test_duplicate_label_rejected(self):
        label = "QA-DUP-" + uuid.uuid4().hex[:6].upper()
        self._create(label)
        with self.assertRaises(AssertionError):
            self.rpc("qr_create_table", p_label=label)

    # ------------------------------------------------------------------
    # T-02: pesanan aktif memblokir; terminal setelah itu diizinkan
    # ------------------------------------------------------------------
    def test_delete_blocks_active_draft_then_allows_terminal(self):
        tid, _, _ = self._create()
        self.sql("insert into qr_drafts(table_id, table_label, client_key) "
                 f"values({tid}, 'QA', 'active-1');")  # status PENDING
        with self.assertRaisesRegex(AssertionError, "table_has_active_orders"):
            self.rpc("qr_delete_table", p_table_id=tid)
        # Meniru sapuan papan: PENDING lewat waktu -> EXPIRED (terminal).
        self.sql("update qr_drafts set status = 'EXPIRED' "
                 f"where table_id = {tid};")
        out = self.rpc("qr_delete_table", p_table_id=tid)
        self.assertEqual(out["drafts_removed"], 1)
        self.assertEqual(
            self.sql(f"select count(*) from qr_drafts where table_id = {tid};"),
            "0")
        self.assertEqual(
            self.sql(f"select count(*) from dining_tables where id = {tid};"),
            "0")

    # ------------------------------------------------------------------
    # T-03: penjualan dipertahankan (tautan dilepas), draft berbayar terhapus
    # ------------------------------------------------------------------
    def test_delete_keeps_sales_rows_detaches_link(self):
        tid, _, _ = self._create()
        sale_id = int(self.sql(
            "insert into sales(receipt_no, table_id, subtotal, total, "
            "idempotency_key) values "
            f"('QA-TBL-{uuid.uuid4().hex[:8]}', {tid}, 10000, 10000, "
            f"'qa-tbl-{uuid.uuid4().hex[:12]}') returning id;"))
        # Draft COMPLETED berbayar (sale_id terisi) = terminal, ikut terhapus.
        self.sql("insert into qr_drafts(table_id, table_label, client_key, "
                 "status, sale_id) values "
                 f"({tid}, 'QA', 'paid-1', 'COMPLETED', {sale_id});")

        out = self.rpc("qr_delete_table", p_table_id=tid)
        self.assertEqual(out["drafts_removed"], 1)
        self.assertEqual(out["sales_detached"], 1)
        # Buku uang utuh: baris sale masih ada, hanya tanpa tautan meja.
        self.assertEqual(
            self.sql(f"select count(*) from sales where id = {sale_id};"), "1")
        self.assertEqual(
            self.sql(f"select table_id::text from sales where id = {sale_id};"),
            "")

    # ------------------------------------------------------------------
    # T-04 / T-05: guard operator & meja tidak ada
    # ------------------------------------------------------------------
    def test_non_operator_rejected(self):
        result = subprocess.run(
            [os.environ.get("PSQL", "psql"), "-XqAt", "-v",
             "ON_ERROR_STOP=1", "--dbname", self.db, "-c",
             "set role authenticated; set request.jwt.claims = '{}'; "
             "select public.qr_delete_table(1);"],
            capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0,
                            "non-operator seharusnya ditolak")
        self.assertIn("operator_required", result.stderr)

    def test_delete_missing_table_rejected(self):
        with self.assertRaisesRegex(AssertionError, "table_not_found"):
            self.rpc("qr_delete_table", p_table_id=999999999)


if __name__ == "__main__":
    unittest.main(verbosity=2)

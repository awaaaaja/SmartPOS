#!/usr/bin/env python3
"""Uji notifikasi realtime draft (migrasi 0024) di database sementara.

DATABASE_URL harus akun PostgreSQL staging/CI dengan izin CREATE DATABASE.
Tidak memakai password operator atau mengubah database bisnis yang ada.
Pola sama dengan test_online_orders.py: bikin DB sementara, terapkan stub +
semua migrasi.

Menguji policy SELECT operator + broadcast publication (dasar push notifikasi
realtime; verifikasi event WebSocket-nya sendiri diuji empiris terpisah):

  T-01  operator (authenticated + klaim email cocok) bisa MEMBACA qr_drafts
        langsung — syarat realtime mengirim event ke pelanggan ini.
  T-02  anon tetap DITOLAK membaca qr_drafts (policy hanya to authenticated).
  T-03  authenticated BUKAN operator dapat 0 baris (RLS is_operator()).
  T-04  qr_drafts terdaftar di publication supabase_realtime (bila ada) —
        tanpa ini realtime tidak pernah mengirim INSERT/UPDATE.
  T-05  operator TIDAK bisa menulis langsung (tanpa policy tulis) — semua
        tulisan tetap lewat RPC SECURITY DEFINER; alur lama tak berubah.
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
    """Kutip literal SQL (string/number/bool/None/list/dict) dengan aman."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        lit = "true" if value else "false"
    elif isinstance(value, (int, float)):
        lit = str(value)
    elif isinstance(value, (list, dict)):
        lit = json.dumps(value).replace("'", "''")
    else:
        lit = str(value).replace("'", "''")
    return f"'{lit}'::{sql_type}" if sql_type else f"'{lit}'"


class DraftRealtimeTest(unittest.TestCase):
    PARAM_TYPES = {
        "qr_online_submit": {
            "p_client_key": "text",
            "p_customer_name": "text",
            "p_customer_phone": "text",
            "p_customer_address": "text",
            "p_pay_intent": "text",
            "p_items": "jsonb",
        },
    }
    OPERATOR_EMAIL = "realtime@example.invalid"

    @classmethod
    def sql(cls, query, *, role=None, db=None):
        prefix = ""
        if role == "operator":
            claims = json.dumps({"email": cls.OPERATOR_EMAIL})
            prefix = (f"set role authenticated; set request.jwt.claims = "
                      f"'{claims}'; ")
        elif role == "bukan_operator":
            claims = json.dumps({"email": "intruder@example.invalid"})
            prefix = (f"set role authenticated; set request.jwt.claims = "
                      f"'{claims}'; ")
        elif role:
            prefix = f"set role {role}; "
        result = subprocess.run(
            [os.environ.get("PSQL", "psql"), "-XqAt", "-v", "ON_ERROR_STOP=1",
             "--dbname", db or cls.db, "-c", prefix + query],
            capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stderr.replace(cls.admin, "<DB_URL>"))
        return result.stdout.strip()

    def rpc(self, fn, *, role="anon", **params):
        types = self.PARAM_TYPES.get(fn, {})
        args = ", ".join(f"{k} => {q(v, types.get(k))}"
                         for k, v in params.items())
        out = self.sql(f"select public.{fn}({args})::text;", role=role)
        return json.loads(out)

    @classmethod
    def setUpClass(cls):
        cls.admin = os.environ["DATABASE_URL"]
        name = "realtime_test_" + uuid.uuid4().hex
        parts = urlsplit(cls.admin)
        cls.db = urlunsplit(parts._replace(path="/" + name))
        cls.sql(f'create database "{name}"', db=cls.admin)
        cls.addClassCleanup(
            lambda: cls.sql(f'drop database "{name}"', db=cls.admin))
        for path in [ROOT / "tests/integration/supabase_stub.sql",
                     *sorted((ROOT / "supabase/migrations").glob("*.sql"))]:
            cls.sql(path.read_text())
        cls.sql(f"""insert into business_settings(id,name,operator_email)
                   values(1,'Realtime QA','{cls.OPERATOR_EMAIL}');""")

    def setUp(self):
        self.suffix = uuid.uuid4().hex[:8].upper()
        cat = int(self.sql(
            "insert into product_categories(name) "
            f"values('Kat {self.suffix}') returning id;"))
        self.product_id = int(self.sql(
            "insert into products(name, price, category_id) "
            f"values('Nasi {self.suffix}', 10000, {cat}) "
            "returning id;"))
        self.phone = "628" + self.suffix.replace("-", "")[:9]

    def _submit(self):
        """Buat satu draft PENDING lewat jalur anon yang sah."""
        return self.rpc(
            "qr_online_submit",
            p_client_key=f"rt-{self.suffix}",
            p_customer_name=f"Realtime {self.suffix}",
            p_customer_phone=self.phone,
            p_customer_address=None,
            p_pay_intent="AT_PLACE",
            p_items=[{"product_id": self.product_id, "qty": 1}],
        )

    # ------------------------------------------------------------------
    # T-01: operator boleh membaca qr_drafts langsung
    # ------------------------------------------------------------------
    def test_operator_can_read_drafts_directly(self):
        out = self._submit()
        rows = self.sql(
            f"select 'Q' || id from qr_drafts where id = {out['draft_id']};",
            role="operator")
        self.assertEqual(rows, f"Q{out['draft_id']}")

    # ------------------------------------------------------------------
    # T-02: anon tetap tertutup rapat
    # ------------------------------------------------------------------
    def test_anon_still_denied(self):
        with self.assertRaisesRegex(AssertionError,
                                    "permission denied|row-level security"):
            self.sql("select id from qr_drafts limit 1;", role="anon")

    # ------------------------------------------------------------------
    # T-03: authenticated bukan operator = 0 baris
    # ------------------------------------------------------------------
    def test_non_operator_sees_no_rows(self):
        out = self._submit()
        rows = self.sql("select id from qr_drafts;", role="bukan_operator")
        self.assertEqual(
            rows, "", f"bukan operator seharusnya tidak melihat baris: {rows}")
        # Barisnya memang ada (dibaca admin — bukan masalah visibilitas data).
        self.assertNotEqual(
            self.sql(f"select id from qr_drafts where id = {out['draft_id']};"),
            "")

    # ------------------------------------------------------------------
    # T-04: qr_drafts di publication supabase_realtime
    # ------------------------------------------------------------------
    def test_drafts_in_realtime_publication(self):
        rows = self.sql(
            "select tablename from pg_publication_tables "
            "where pubname = 'supabase_realtime' and schemaname = 'public' "
            "and tablename = 'qr_drafts';")
        self.assertEqual(
            rows, "qr_drafts",
            "qr_drafts harus ikut publication supabase_realtime "
            "(stub CI membuat publication; guard migrasi menambahkan tabel)")

    # ------------------------------------------------------------------
    # T-05: tulis langsung tetap ditolak (semua lewat RPC)
    # ------------------------------------------------------------------
    def test_direct_write_still_denied_for_operator(self):
        out = self._submit()
        with self.assertRaisesRegex(
                AssertionError, "row-level security|permission denied"):
            self.sql(
                "update qr_drafts set status = 'CANCELLED' "
                f"where id = {out['draft_id']};", role="operator")
        with self.assertRaisesRegex(
                AssertionError, "row-level security|permission denied"):
            self.sql(
                "insert into qr_drafts(table_id, table_label, status, "
                "client_key) select id, label, 'PENDING', "
                f"'direct-{self.suffix}' from dining_tables limit 1;",
                role="operator")


if __name__ == "__main__":
    unittest.main(verbosity=2)

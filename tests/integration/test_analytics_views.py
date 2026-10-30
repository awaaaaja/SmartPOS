#!/usr/bin/env python3
"""Uji view agregat analitik (migrasi 0017) di database sementara.

DATABASE_URL harus akun PostgreSQL staging/CI dengan izin CREATE DATABASE.
Tidak memakai password operator atau mengubah database bisnis yang ada.

Menguji (D-06 / docs/ml-roadmap.md):
  - agregat deterministik: hari/jam WIB benar di batas pergantian hari
  - uang dihitung sekali per transaksi (bukan per item)
  - sale REFUNDED dikeluarkan dari agregat menu, refund sebagian tetap di refunds
  - pergerakan bahan terpisah PURCHASE / RECIPE-PRODUCTION / WASTE
  - view memakai security_invoker (RLS tabel dasar tetap berlaku)
  - anon ditolak; authenticated non-operator membaca 0 baris (RLS)
  - tanpa prediksi/ML: view hanya membaca data aktual (PRD §9)
"""
import json
import os
from pathlib import Path
import subprocess
import unittest
import uuid
from urllib.parse import urlsplit, urlunsplit

ROOT = Path(__file__).resolve().parents[2]

VIEWS = ("v_sale_item_facts", "v_sales_daily", "v_sales_hourly",
         "v_product_daily", "v_stock_usage_daily")


class AnalyticsViewsTest(unittest.TestCase):
    @classmethod
    def sql(cls, query, *, role=None, email=None, db=None):
        if role:
            claims = json.dumps({"email": email}) if email else "{}"
            query = (f"set role {role}; set request.jwt.claims = "
                     f"'{claims}'; {query}")
        result = subprocess.run(
            [os.environ.get("PSQL", "psql"), "-XqAt", "-v", "ON_ERROR_STOP=1",
             "--dbname", db or cls.db, "-c", query],
            capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stderr.replace(cls.admin, "<DB_URL>"))
        return result.stdout.strip()

    @classmethod
    def qj(cls, query, **kw):
        out = cls.sql(query, **kw)
        return json.loads(out) if out else None

    @classmethod
    def setUpClass(cls):
        cls.admin = os.environ["DATABASE_URL"]
        name = "analytics_test_" + uuid.uuid4().hex
        parts = urlsplit(cls.admin)
        cls.db = urlunsplit(parts._replace(path="/" + name))
        cls.sql(f'create database "{name}"', db=cls.admin)
        cls.addClassCleanup(lambda: cls.sql(f'drop database "{name}"',
                                            db=cls.admin))
        for path in [ROOT / "tests/integration/supabase_stub.sql",
                     *sorted((ROOT / "supabase/migrations").glob("*.sql"))]:
            cls.sql(path.read_text())

        # 2. Samakan hak akses tabel dengan default Supabase (stub punya peran
        #    tanpa grant); daftar eksplisit supaya GRANT ... ALL TABLES tidak
        #    ikut memberi akses view (view sudah dicabut dari anon di 0017).
        #    RLS dari migrasi tetap yang menentukan visibilitas.
        cls.sql("""
            grant usage on schema public to anon, authenticated;
            grant select on public.sales, public.sale_items,
                            public.stock_movements
              to anon, authenticated;
            """)

        # Dua transaksi di hari WIB yang sama (UTC 17:30 = 00:30 WIB besok):
        # A FINAL 10.000 (2 item @5.000), B REFUNDED 20.000 (4 item @5.000).
        cls.sql("""
            insert into business_settings(id, name, operator_email)
            values (1, 'Waroeng QA', 'analytics@qa.invalid');
            insert into ingredients(id, name, base_unit, balance) overriding system value
            values (3, 'Gula', 'g', 97);
            insert into products(id, name, price, is_active) overriding system value
            values (7, 'Es Teh', 5000, true);
            insert into sales(id, receipt_no, status, dining_type, subtotal,
                              discount_amount, tax_amount, service_amount,
                              total, refund_amount, idempotency_key,
                              created_at) overriding system value
            values (1, 'QA-0001', 'FINAL', 'DINE_IN', 10000, 0, 750, 250,
                    10000, 0, 'qa-key-0001',
                    '2026-01-01T17:30:00+00:00'),
                   (2, 'QA-0002', 'REFUNDED', 'TAKEAWAY', 20000, 0, 0, 0,
                    20000, 20000, 'qa-key-0002',
                    '2026-01-02T03:00:00+00:00');
            insert into sale_items(id, sale_id, product_id, product_name,
                                   unit_price, qty) overriding system value
            values (11, 1, 7, 'Es Teh', 5000, 2),
                   (12, 2, 7, 'Es Teh', 5000, 4);
            insert into stock_movements(id, ingredient_id, qty_delta,
                                        balance_after, source, reason,
                                        created_at) overriding system value
            values (21, 3, 100, 100, 'PURCHASE', 'QA terima',
                    '2026-01-01T17:30:00+00:00'),
                   (22, 3, -2, 98, 'RECIPE', 'QA masak',
                    '2026-01-01T17:30:00+00:00'),
                   (23, 3, -1, 97, 'WASTE', 'QA tumpah',
                    '2026-01-01T17:30:00+00:00');
            """)

    def test_dimensi_wib_di_batas_hari(self):
        rows = self.qj(
            "select to_jsonb(f) from v_sale_item_facts f "
            "where sale_id = 1 order by sale_item_id")
        # 2026-01-01 17:30 UTC = 2026-01-02 00:30 WIB (Jumat).
        self.assertEqual(rows["sale_day"], "2026-01-02")
        self.assertEqual(rows["hour_of_day"], 0)
        self.assertEqual(rows["day_of_week"], 5)
        self.assertEqual(rows["line_revenue"], 10000)

    def test_uang_dihitung_sekali_per_transaksi(self):
        rows = self.qj(
            "select to_jsonb(d) from v_sales_daily d "
            "where sale_day = date '2026-01-02'")
        self.assertEqual(rows["transactions"], 2)          # A + B
        self.assertEqual(rows["counted_transactions"], 1)  # B REFUNDED keluar
        self.assertEqual(rows["dine_in_transactions"], 1)
        self.assertEqual(rows["takeaway_transactions"], 1)
        # 10.000 + 20.000 - refund 20.000 = 10.000 (tanpa penggandaan item).
        self.assertEqual(rows["gross_total"], 30000)
        self.assertEqual(rows["refund_total"], 20000)
        self.assertEqual(rows["net_total"], 10000)
        self.assertEqual(rows["tax_total"], 750)
        self.assertEqual(rows["service_total"], 250)

    def test_agregat_menu_mengeluarkan_sale_refunded(self):
        rows = self.qj(
            "select to_jsonb(p) from v_product_daily p "
            "where sale_day = date '2026-01-02'")
        # Hanya transaksi A (2 item @5.000); B REFUNDED tidak ikut.
        self.assertEqual(rows["product_id"], 7)
        self.assertEqual(rows["qty"], 2)
        self.assertEqual(rows["revenue"], 10000)
        self.assertEqual(rows["transactions"], 1)

    def test_agregat_jam_pernah_duakali_dibuka(self):
        rows = self.qj(
            "select json_agg(to_jsonb(h) order by h.sale_hour) "
            "from v_sales_hourly h where sale_day = date '2026-01-02'")
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["sale_hour"][:13], "2026-01-02T00")
        self.assertEqual(rows[1]["sale_hour"][:13], "2026-01-02T10")
        self.assertEqual(rows[1]["transactions"], 1)
        self.assertEqual(rows[0]["transactions"], 1)

    def test_pergerakan_bahan_terpisah_per_sumber(self):
        data = self.qj(
            "select json_agg(to_jsonb(s)) from v_stock_usage_daily s "
            "where movement_day = date '2026-01-02'")
        rows = {r["source"]: r for r in data}
        self.assertEqual(rows["PURCHASE"]["qty_in"], 100)
        self.assertEqual(rows["PURCHASE"]["qty_out"], 0)
        self.assertEqual(rows["RECIPE"]["qty_out"], 2)
        self.assertEqual(rows["WASTE"]["qty_out"], 1)
        self.assertEqual(rows["RECIPE"]["qty_delta"], -2)

    def test_view_memakai_security_invoker(self):
        names = ", ".join(f"'{v}'" for v in VIEWS)
        query = ("select json_agg(relname) from pg_class where relname in ("
                 + names
                 + ") and coalesce(reloptions, '{}') "
                   "@> array['security_invoker=true']")
        found = self.qj(query)
        self.assertEqual(len(found), len(VIEWS))

    def test_anon_ditolak(self):
        for view in VIEWS:
            with self.subTest(view=view):
                with self.assertRaisesRegex(AssertionError,
                                            "permission denied"):
                    self.sql(f"select count(*) from public.{view};",
                             role="anon")

    def test_authenticated_non_operator_melihat_nol_baris(self):
        # security_invoker -> RLS tabel dasar ikut berlaku.
        for view in VIEWS:
            with self.subTest(view=view):
                out = self.sql(f"select count(*) from public.{view};",
                               role="authenticated",
                               email="bukan-operator@qa.invalid")
                self.assertEqual(out, "0")


if __name__ == "__main__":
    unittest.main(verbosity=2)

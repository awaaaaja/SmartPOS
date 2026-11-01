#!/usr/bin/env python3
"""Uji rekomendasi non-ML (Fase R1, RFC r1-01 & r1-02) di database sementara.

DATABASE_URL harus akun PostgreSQL staging/CI dengan izin CREATE DATABASE.
Tidak memakai password operator atau mengubah database bisnis yang ada.
Pola sama dengan test_mutation_retry.py: bikin DB sementara, terapkan stub +
semua migrasi, jalankan sebagai role authenticated dengan klaim operator.

Menguji dua RPC statistik deskriptif (tanpa model, tanpa prediksi):

  R1-01  inv_hpp_alerts(threshold, window)
         - bahan dengan riwayat pembelian RECEIVED dalam jendela & unit_cost
           terkini menyimpang >= threshold% muncul, dengan arah NAIK/TURUN dan
           dampak HPP per porsi untuk tiap menu resep aktif;
         - rata-rata pembanding TERTIMBANG (sum total / sum qty), bukan
           rerata baris;
         - threshold 500% -> daftar kosong (jujur, bukan angka karangan);
         - threshold di luar [1,500] / window di luar [7,730] ditolak.

  R1-02  exp_energy_calibration(from, to)
         - default 30 hari WIB inklusif; rentang invalid ditolak;
         - deviasi/faktor HANYA dari jenis yang punya KEDUA sisi
           (ESTIMATED > 0 dan ACTUAL > 0) — LPG tanpa tagihan asli tidak
           mengencerkan deviasi listrik;
         - enough_data=false + deviasi/faktor null saat belum ada tagihan
           asli (bukan nol karangan);
         - anon/non-operator ditolak (42501).

Kejujuran angka: peringatan hanya untuk bahan yang benar-benar punya riwayat
dalam jendela; tanpa pembanding = tidak masuk daftar (bukan deviasi 0).
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

    sql_type: tipe eksplisit (mis. 'date', 'text') saat pemilihan overload
    butuh tipa pasti — panggilan argumen bernama tak bisa resolve dari
    literal string ('unknown'). Angka literal dibiarkan (integer bawaan,
    koerse rapi ke numeric/bigint); JSON diserialisasi utuh.
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


class RecommendationsTest(unittest.TestCase):
    # Tipe parameter string/JSON dari definisi fungsi (lihat migrasi) —
    # dibaca sekali agar panggilan argumen bernama resolve overload dengan
    # tepat tanpa mengulang cast di tiap situs pemanggilan.
    PARAM_TYPES = {
        "inv_save_ingredient": {"p_id": "bigint", "p_name": "text",
                                "p_base_unit": "text"},
        "inv_create_purchase": {"p_supplier": "text", "p_items": "jsonb",
                                "p_status": "text",
                                "p_purchased_at": "date",
                                "p_idempotency_key": "text"},
        "inv_save_recipe": {"p_items": "jsonb"},
        "exp_save": {"p_idempotency_key": "text", "p_type": "text",
                     "p_description": "text", "p_kind": "text",
                     "p_expense_date": "date", "p_evidence_url": "text"},
        "exp_energy_calibration": {"p_from": "date", "p_to": "date"},
    }

    @classmethod
    def sql(cls, query, *, operator=False, role="authenticated", db=None):
        if operator:
            claims = json.dumps({"email": "reco@example.invalid"})
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
        # Pakai argumen bernama (name => value) supaya parameter yang tidak
        # diberi nilai jatuh ke default DB dan pemilihan overload tidak
        # bergantung pada posisi. Angka/bool/null: literal bawaan Postgres;
        # string/JSON: cast eksplisit (PARAM_TYPES).
        args = ", ".join(f"{k} => {q(v, types.get(k))}"
                         for k, v in params.items())
        # Cast ::text -> psql mencetak JSON ketat (psql menampilkan jsonb
        # dengan kunci tanpa kutip; ::text menormalkan ke JSON valid).
        out = self.sql(
            f"select public.{fn}({args})::text;", operator=True)
        return json.loads(out)

    @classmethod
    def setUpClass(cls):
        cls.admin = os.environ["DATABASE_URL"]
        name = "reco_test_" + uuid.uuid4().hex
        parts = urlsplit(cls.admin)
        cls.db = urlunsplit(parts._replace(path="/" + name))
        cls.sql(f'create database "{name}"', db=cls.admin)
        cls.addClassCleanup(
            lambda: cls.sql(f'drop database "{name}"', db=cls.admin))
        for path in [ROOT / "tests/integration/supabase_stub.sql",
                     *sorted((ROOT / "supabase/migrations").glob("*.sql"))]:
            cls.sql(path.read_text())
        cls.sql("""insert into business_settings(id,name,operator_email)
                   values(1,'Reco QA','reco@example.invalid');""")

    # ------------------------------------------------------------------
    # R1-01: inv_hpp_alerts
    # ------------------------------------------------------------------
    def test_hpp_alert_weighted_avg_and_impact(self):
        suffix = uuid.uuid4().hex[:6].upper()
        ing_id = int(self.rpc("inv_save_ingredient", p_name=f"CABAI-{suffix}",
                              p_base_unit="g", p_reorder_level=0,
                              p_unit_cost=0)["id"])
        for qty_g, harga in [(2, 3000), (10, 17000)]:
            po = self.rpc("inv_create_purchase", p_supplier="Toko QA",
                          p_items=[{"ingredient_id": ing_id, "qty": qty_g,
                                    "unit": "g", "total_price": harga}],
                          p_status="RECEIVED",
                          p_idempotency_key=uuid.uuid4().hex)
            self.assertEqual(po["status"], "RECEIVED")
        # Naikkan unit_cost ke 2.000 -> deviasi +20% dari 1.666,67.
        upd = self.rpc("inv_save_ingredient", p_id=ing_id,
                       p_name=f"CABAI-{suffix}", p_base_unit="g",
                       p_reorder_level=0, p_unit_cost=2000)
        self.assertEqual(upd["unit_cost"], 2000)

        # Produk + resep aktif: yield 2 porsi, pakai 400 g cabai.
        # Fixture kategori/produk ditulis sebagai admin (bukan lewat RLS
        # authenticated) — pola test_mutation_retry.py; RPC di bawah tetap
        # berjalan sebagai authenticated+operator (SECURITY DEFINER).
        cat = self.sql("select id from product_categories limit 1;")
        if not cat:
            cat = self.sql(
                "insert into product_categories(name) "
                f"values('QA-{suffix}') returning id;")
        cat_id = int(cat)
        pid = int(self.sql(
            f"insert into products(category_id,name,price,is_active) "
            f"values({cat_id},'NASGOR-{suffix}',25000,true) returning id;"))
        self.rpc("inv_save_recipe", p_product_id=pid, p_yield_qty=2,
                 p_items=[{"ingredient_id": ing_id, "qty": 400}])

        alerts = self.rpc("inv_hpp_alerts", p_threshold_pct=10,
                          p_window_days=90)["alerts"]
        mine = [a for a in alerts if a["ingredient_id"] == ing_id]
        self.assertEqual(len(mine), 1, f"peringatan untuk bahan uji: {alerts}")
        a = mine[0]
        self.assertEqual(a["direction"], "NAIK")
        self.assertEqual(a["delta_pct"], 20.0)
        # Rata-rata tertimbang = 20.000 / 12 = 1.666,67 -> dibulatkan 1667.
        self.assertEqual(a["avg_cost"], 1667)
        self.assertEqual(a["purchases"], 2)
        self.assertEqual(len(a["products"]), 1)
        p = a["products"][0]
        self.assertEqual(p["product_name"], f"NASGOR-{suffix}")
        # delta/unit = 2000 - 1666,67 = 333,33 per g; * 400 g / yield 2
        # = 66.667 per porsi.
        self.assertAlmostEqual(p["hpp_delta_per_portion"], 66667, delta=2)

    def test_hpp_alert_threshold_too_high_is_empty(self):
        alerts = self.rpc("inv_hpp_alerts", p_threshold_pct=500,
                          p_window_days=90)["alerts"]
        self.assertEqual(alerts, [])

    def test_hpp_alert_rejects_out_of_range_params(self):
        with self.assertRaises(AssertionError):
            self.rpc("inv_hpp_alerts", p_threshold_pct=0, p_window_days=90)
        with self.assertRaises(AssertionError):
            self.rpc("inv_hpp_alerts", p_threshold_pct=10, p_window_days=6)

    # ------------------------------------------------------------------
    # R1-02: exp_energy_calibration
    # ------------------------------------------------------------------
    def test_energy_calibration_balanced_subset_only(self):
        # Listrik seimbang: ESTIMATED 2.880 vs ACTUAL 3.200 (+11,1%).
        for kind, amount in [("ESTIMATED", 2880), ("ACTUAL", 3200)]:
            self.rpc("exp_save", p_type="LISTRIK",
                     p_description=f"Kalibrasi listrik {kind}",
                     p_amount=amount, p_kind=kind,
                     p_idempotency_key=uuid.uuid4().hex)
        # LPG hanya ESTIMATED -> tidak boleh mengencerkan deviasi listrik.
        self.rpc("exp_save", p_type="LPG", p_description="Kalibrasi LPG",
                 p_amount=2750, p_kind="ESTIMATED",
                 p_idempotency_key=uuid.uuid4().hex)

        cal = self.rpc("exp_energy_calibration", p_from=None, p_to=None)
        self.assertTrue(cal["enough_data"])
        # Deviasi dari subset seimbang: (3200 - 2880)/2880 = +11,1%.
        self.assertEqual(cal["deviation_pct"], 11.1)
        self.assertEqual(cal["compared_estimated"], 2880)
        self.assertEqual(cal["compared_actual"], 3200)
        # estimated_total tetap memuat LPG (field tampilan berbeda).
        self.assertEqual(cal["estimated_total"], 5630)
        self.assertEqual(cal["suggested_factor"], 1.111)
        by_type = {t["type"]: t for t in cal["by_type"]}
        # LPG tanpa actual: deviasi/faktor null, bukan 0.
        self.assertIsNone(by_type["LPG"]["deviation_pct"])
        self.assertIsNone(by_type["LPG"]["suggested_factor"])
        self.assertEqual(by_type["LPG"]["estimated"], 2750)

    def test_energy_calibration_empty_range_is_honest_null(self):
        cal = self.rpc("exp_energy_calibration", p_from="2020-01-01",
                       p_to="2020-01-31")
        self.assertFalse(cal["enough_data"])
        self.assertIsNone(cal["deviation_pct"])
        self.assertIsNone(cal["suggested_factor"])
        self.assertEqual(cal["by_type"], [])

    def test_energy_calibration_rejects_inverted_range(self):
        with self.assertRaises(AssertionError):
            self.rpc("exp_energy_calibration", p_from="2026-11-02",
                     p_to="2026-11-01")

    # ------------------------------------------------------------------
    # Guard: non-operator ditolak (errcode 42501 -> psql error).
    # ------------------------------------------------------------------
    def test_non_operator_rejected(self):
        # Menjalankan sebagai role authenticated biasa (bukan operator).
        for fn, params in [
            ("inv_hpp_alerts", {"p_threshold_pct": 10, "p_window_days": 90}),
            ("exp_energy_calibration", {"p_from": None, "p_to": None}),
        ]:
            types = self.PARAM_TYPES.get(fn, {})
            args = ", ".join(f"{k} => {q(v, types.get(k))}"
                             for k, v in params.items())
            result = subprocess.run(
                [os.environ.get("PSQL", "psql"), "-XqAt", "-v",
                 "ON_ERROR_STOP=1", "--dbname", self.db, "-c",
                 f"set role authenticated; set request.jwt.claims = '{{}}'; "
                 f"select public.{fn}({args});"],
                capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0,
                                f"{fn} seharusnya ditolak untuk non-operator")
            self.assertIn("operator_required", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)

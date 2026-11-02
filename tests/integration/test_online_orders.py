#!/usr/bin/env python3
"""Uji pesanan online (migrasi 0023) di database sementara.

DATABASE_URL harus akun PostgreSQL staging/CI dengan izin CREATE DATABASE.
Tidak memakai password operator atau mengubah database bisnis yang ada.
Pola sama dengan test_manual_orders.py: bikin DB sementara, terapkan stub +
semua migrasi; RPC online dipanggil sebagai role ANON (tanpa login), papan
pesanan dibaca sebagai role authenticated dengan klaim operator.

Menguji get_online_menu & qr_online_submit:

  T-01  menu online terbaca TANPA token & TANPA login; meja virtual
        "Pesanan Online" dibuat otomatis (self-healing bila dihapus).
  T-02  submit AT_PLACE (Bayar di tempat): nama & WA wajib tersimpan, alamat
        opsional, lahir PENDING dengan masa aktif 24 jam, subtotal = hitungan
        server (harga snapshot — harga kiriman klien diabaikan).
  T-03  COD: alamat WAJIB (invalid_customer_address bila kosong), alamat
        tersimpan utuh bila diisi.
  T-04  input tidak valid ditolak: nama kosong/kepanjangan, WA kosong,
        pay_intent di luar AT_PLACE|COD, items kosong, client key pendek,
        produk arsip (product_unavailable), qty 0 (invalid_qty).
  T-05  idempotensi: client_key sama -> draft yang sama (tanpa baris dobel).
  T-06  rate limit per nomor WA: 6 kiriman dalam 10 menit -> rate_limited.
  T-07  draft muncul di papan operator (qr_list_drafts) lengkap dengan
        alamat & niat bayar; anon TIDAK bisa membaca tabel draft langsung
        (tanpa policy RLS).

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


class OnlineOrdersTest(unittest.TestCase):
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
    OPERATOR_EMAIL = "online@example.invalid"

    @classmethod
    def sql(cls, query, *, role=None, db=None):
        prefix = ""
        if role == "operator":
            claims = json.dumps({"email": cls.OPERATOR_EMAIL})
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
        name = "online_test_" + uuid.uuid4().hex
        parts = urlsplit(cls.admin)
        cls.db = urlunsplit(parts._replace(path="/" + name))
        cls.sql(f'create database "{name}"', db=cls.admin)
        cls.addClassCleanup(
            lambda: cls.sql(f'drop database "{name}"', db=cls.admin))
        for path in [ROOT / "tests/integration/supabase_stub.sql",
                     *sorted((ROOT / "supabase/migrations").glob("*.sql"))]:
            cls.sql(path.read_text())
        cls.sql(f"""insert into business_settings(id,name,operator_email)
                   values(1,'Online QA','{cls.OPERATOR_EMAIL}');""")

    def setUp(self):
        self.suffix = uuid.uuid4().hex[:8].upper()
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
        mod = int(self.sql(
            "insert into modifiers(name, price_delta) "
            f"values('Pedas {self.suffix}', 2000) returning id;"))
        self.sql("insert into product_modifiers(product_id, modifier_id) "
                 f"values({self.product_id}, {mod});")
        self.mod_id = mod
        self.phone = "628" + self.suffix.replace("-", "")[:9]

    def _key(self, n=0):
        return f"on-{self.suffix}-{n}"

    # ------------------------------------------------------------------
    # T-01: menu tanpa token + meja virtual self-healing
    # ------------------------------------------------------------------
    def test_online_menu_without_token_and_self_healing_table(self):
        out = self.rpc("get_online_menu")
        self.assertIn("categories", out)
        names = [c["name"] for c in out["categories"]]
        self.assertIn(f"Kat {self.suffix}", names)
        prod = out["categories"][names.index(f"Kat {self.suffix}")][
            "products"][0]
        self.assertEqual(prod["name"], f"Nasi {self.suffix}")
        self.assertEqual(prod["price"], 10000)
        self.assertEqual(out["table"]["label"], "Pesanan Online")

        # Self-healing: baris meja virtual dihapus -> RPC berikutnya
        # membuatnya lagi (seluruh alur lama tetap utuh). Draft dulu di DB
        # sementara ini dihapus karena jadi rujukan FK.
        old_id = out["table"]["id"]
        self.sql(f"delete from qr_drafts where table_id = {old_id};")
        self.sql("delete from dining_tables where label = 'Pesanan Online';")
        again = self.rpc("get_online_menu")
        self.assertEqual(again["table"]["label"], "Pesanan Online")
        self.assertGreater(again["table"]["id"], 0)

    # ------------------------------------------------------------------
    # T-02: submit AT_PLACE — wajib nama & WA, harga snapshot server
    # ------------------------------------------------------------------
    def test_submit_at_place(self):
        out = self.rpc(
            "qr_online_submit",
            p_client_key=self._key(),
            p_customer_name=f"Budi {self.suffix}",
            p_customer_phone=self.phone,
            p_customer_address="",
            p_pay_intent="AT_PLACE",
            p_items=[{"product_id": self.product_id, "qty": 2,
                      "modifier_ids": [self.mod_id],
                      "price": 1,   # harga palsu dari klien: DIABAIKAN
                      "note": "tanpa sendok"}],
        )
        self.assertEqual(out["status"], "PENDING",
                         "pesanan online menunggu konfirmasi operator")
        self.assertEqual(out["table_label"], "Pesanan Online")
        self.assertEqual(out["customer_name"], f"Budi {self.suffix}")
        self.assertEqual(out["customer_phone"], self.phone)
        self.assertIsNone(out["customer_address"],
                          "AT_PLACE: alamat bersifat opsional")
        self.assertEqual(out["pay_intent"], "AT_PLACE")
        self.assertIsNone(out["pay_method"])
        # Snapshot server: (10000 + 2000) * 2 — bukan harga kiriman klien.
        self.assertEqual(out["subtotal"], 24000)
        item = out["items"][0]
        self.assertEqual(item["unit_price"], 12000)
        self.assertEqual(item["qty"], 2)
        self.assertEqual(item["note"], "tanpa sendok")
        # Masa aktif 24 jam agar operator sempat membuka papan pesanan.
        secs = float(self.sql(
            "select extract(epoch from expires_at - created_at) "
            f"from qr_drafts where id = {out['draft_id']};"))
        self.assertGreaterEqual(secs, 24 * 3600 - 60)

    # ------------------------------------------------------------------
    # T-03: COD — alamat wajib
    # ------------------------------------------------------------------
    def test_cod_requires_address(self):
        with self.assertRaisesRegex(AssertionError,
                                    "invalid_customer_address"):
            self.rpc("qr_online_submit",
                     p_client_key=self._key(1),
                     p_customer_name=f"Cod {self.suffix}",
                     p_customer_phone=self.phone,
                     p_customer_address="   ",
                     p_pay_intent="COD",
                     p_items=[{"product_id": self.product_id, "qty": 1}])

        out = self.rpc(
            "qr_online_submit",
            p_client_key=self._key(2),
            p_customer_name=f"Cod {self.suffix}",
            p_customer_phone=self.phone,
            p_customer_address=f"Jl. Mawar {self.suffix} No. 7",
            p_pay_intent="COD",
            p_items=[{"product_id": self.product_id, "qty": 1}],
        )
        self.assertEqual(out["pay_intent"], "COD")
        self.assertEqual(out["customer_address"],
                         f"Jl. Mawar {self.suffix} No. 7")
        self.assertEqual(out["status"], "PENDING")

    # ------------------------------------------------------------------
    # T-04: input tidak valid ditolak semua
    # ------------------------------------------------------------------
    def test_invalid_inputs_rejected(self):
        base = dict(
            p_customer_phone=self.phone,
            p_pay_intent="AT_PLACE",
            p_items=[{"product_id": self.product_id, "qty": 1}],
        )

        def submit(key, **over):
            args = dict(base, p_client_key=key,
                        p_customer_name=f"X {self.suffix}",
                        p_customer_address=None)
            args.update(over)
            return self.rpc("qr_online_submit", **args)

        with self.assertRaisesRegex(AssertionError, "missing_client_key"):
            submit("pendek")
        with self.assertRaisesRegex(AssertionError, "invalid_customer_name"):
            submit(self._key(1), p_customer_name="   ")
        with self.assertRaisesRegex(AssertionError, "invalid_customer_name"):
            submit(self._key(2), p_customer_name="x" * 61)
        with self.assertRaisesRegex(AssertionError,
                                    "invalid_customer_phone"):
            submit(self._key(3), p_customer_phone="  ")
        with self.assertRaisesRegex(AssertionError, "invalid_pay_intent"):
            submit(self._key(4), p_pay_intent="PAY_NOW")
        with self.assertRaisesRegex(AssertionError, "invalid_items"):
            submit(self._key(5), p_items=[])
        with self.assertRaisesRegex(AssertionError, "product_unavailable"):
            submit(self._key(6),
                   p_items=[{"product_id": self.archived_id, "qty": 1}])
        with self.assertRaisesRegex(AssertionError, "invalid_qty"):
            submit(self._key(7),
                   p_items=[{"product_id": self.product_id, "qty": 0}])

        # Kebersihan: tidak ada draft setengah jadi tertinggal.
        self.assertEqual(
            self.sql("select count(*) from qr_drafts "
                     f"where table_label = 'Pesanan Online' "
                     f"and customer_name = 'X {self.suffix}';"), "0")

    # ------------------------------------------------------------------
    # T-05: idempotensi — retry client_key sama tidak menggandakan
    # ------------------------------------------------------------------
    def test_idempotent_replay(self):
        args = dict(
            p_customer_name=f"Idem {self.suffix}",
            p_customer_phone=self.phone,
            p_customer_address=None,
            p_pay_intent="AT_PLACE",
            p_items=[{"product_id": self.product_id, "qty": 1}],
        )
        first = self.rpc("qr_online_submit", p_client_key=self._key(),
                         **args)
        self.assertFalse(first["idempotent_replay"])
        replay = self.rpc("qr_online_submit", p_client_key=self._key(),
                          **args)
        self.assertTrue(replay["idempotent_replay"])
        self.assertEqual(replay["draft_id"], first["draft_id"])
        self.assertEqual(
            self.sql("select count(*) from qr_drafts "
                     f"where client_key = '{self._key()}';"), "1")

    # ------------------------------------------------------------------
    # T-06: rate limit per nomor WA (5 per 10 menit)
    # ------------------------------------------------------------------
    def test_rate_limit_per_phone(self):
        last = None
        for n in range(5):
            last = self.rpc(
                "qr_online_submit",
                p_client_key=self._key(n),
                p_customer_name=f"Flood {self.suffix}",
                p_customer_phone=self.phone,
                p_customer_address=None,
                p_pay_intent="AT_PLACE",
                p_items=[{"product_id": self.product_id, "qty": 1}],
            )
        self.assertFalse(last["idempotent_replay"])
        with self.assertRaisesRegex(AssertionError, "rate_limited"):
            self.rpc("qr_online_submit",
                     p_client_key=self._key(99),
                     p_customer_name=f"Flood {self.suffix}",
                     p_customer_phone=self.phone,
                     p_customer_address=None,
                     p_pay_intent="AT_PLACE",
                     p_items=[{"product_id": self.product_id, "qty": 1}])

    # ------------------------------------------------------------------
    # T-07: papan operator melihat draft online; anon tertutup rapat
    # ------------------------------------------------------------------
    def test_draft_on_operator_board_and_rls(self):
        out = self.rpc(
            "qr_online_submit",
            p_client_key=self._key(),
            p_customer_name=f"Papan {self.suffix}",
            p_customer_phone=self.phone,
            p_customer_address=f"Jl. Kenanga {self.suffix}",
            p_pay_intent="COD",
            p_items=[{"product_id": self.product_id, "qty": 1}],
        )
        board = json.loads(self.sql(
            "select public.qr_list_drafts()::text;", role="operator"))
        mine = [d for d in board if d["draft_id"] == out["draft_id"]]
        self.assertEqual(len(mine), 1, "pesanan online tampil di papan")
        card = mine[0]
        self.assertEqual(card["table_label"], "Pesanan Online")
        self.assertEqual(card["customer_name"], f"Papan {self.suffix}")
        self.assertEqual(card["customer_phone"], self.phone)
        self.assertEqual(card["customer_address"],
                         f"Jl. Kenanga {self.suffix}")
        self.assertEqual(card["pay_intent"], "COD")
        self.assertEqual(card["status"], "PENDING")

        # Anon tidak bisa membaca/menulis tabel draft langsung (tanpa policy).
        with self.assertRaisesRegex(AssertionError,
                                    "permission denied|row-level security"):
            self.sql("select id from qr_drafts limit 1;", role="anon")


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Uji RPC settings_save (K06-08: pengaturan bisa diedit dari UI).

DATABASE_URL harus akun PostgreSQL staging/CI dengan izin CREATE DATABASE.
Tidak memakai password operator atau mengubah database bisnis yang ada.

Menguji:
  - operator menyimpan nama/alamat/zona waktu/tarif -> baris terbaru + audit
  - non-operator ditolak 42501 operator_required
  - anon tanpa grant tidak bisa memanggil
  - validasi server: nama, alamat, zona waktu, pajak, biaya layanan
  - kegagalan validasi tidak mengubah data
"""
import json
import os
from pathlib import Path
import subprocess
import unittest
import uuid
from urllib.parse import urlsplit, urlunsplit

ROOT = Path(__file__).resolve().parents[2]


class SettingsEditTest(unittest.TestCase):
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
    def setUpClass(cls):
        cls.admin = os.environ["DATABASE_URL"]
        name = "settings_test_" + uuid.uuid4().hex
        parts = urlsplit(cls.admin)
        cls.db = urlunsplit(parts._replace(path="/" + name))
        cls.sql(f'create database "{name}"', db=cls.admin)
        cls.addClassCleanup(lambda: cls.sql(f'drop database "{name}"',
                                            db=cls.admin))
        for path in [ROOT / "tests/integration/supabase_stub.sql",
                     *sorted((ROOT / "supabase/migrations").glob("*.sql"))]:
            cls.sql(path.read_text())
        cls.sql("""insert into business_settings
                     (id, name, address, timezone, operator_email,
                      tax_rate, service_rate)
                   values (1, 'Waroeng MeJeng', 'Jl. Contoh 1', 'Asia/Jakarta',
                           'operator@mejeng.id', 0.10, 0.05);""")

    def save(self, **kw):
        args = {"name": "'Waroeng MeJeng Baru'", "address": "'Jl. Baru No. 7'",
                "timezone": "'Asia/Makassar'", "tax": "0.11",
                "service": "0.025"}
        args.update(kw)
        return self.sql(
            "select public.settings_save({name}, {address}, {timezone}, "
            "{tax}, {service});".format(**args),
            role="authenticated", email="operator@mejeng.id")

    def test_operator_bisa_menyimpan_dengan_audit(self):
        row = json.loads(self.save())
        self.assertEqual(row["name"], "Waroeng MeJeng Baru")
        self.assertEqual(row["timezone"], "Asia/Makassar")
        self.assertEqual(row["tax_rate"], 0.11)
        self.assertEqual(row["service_rate"], 0.025)

        stored = json.loads(self.sql(
            "select to_jsonb(b) from business_settings b where id = 1"))
        self.assertEqual(stored["name"], "Waroeng MeJeng Baru")
        self.assertGreater(stored["updated_at"], stored["created_at"])

        audit = json.loads(self.sql(
            "select to_jsonb(a) from audit_events a where entity = "
            "'business_settings' order by id desc limit 1"))
        self.assertEqual(audit["action"], "UPDATE")
        self.assertEqual(audit["detail"]["after"]["name"],
                         "Waroeng MeJeng Baru")
        self.assertIn("before", audit["detail"])

    def test_non_operator_ditolak(self):
        with self.assertRaisesRegex(AssertionError, "operator_required"):
            self.sql("select public.settings_save('Hacker', null, "
                     "'Asia/Jakarta', 0, 0);",
                     role="authenticated", email="staff@mejeng.id")

    def test_anon_tanpa_grant(self):
        with self.assertRaisesRegex(AssertionError,
                                    "permission denied for function"):
            self.sql("select public.settings_save('Anon', null, "
                     "'Asia/Jakarta', 0, 0);", role="anon")

    def test_validasi_server(self):
        before = json.loads(self.sql(
            "select to_jsonb(b) from business_settings b where id = 1"))
        cases = [
            ("invalid_name",
             "select public.settings_save('  ', null, 'Asia/Jakarta', 0, 0);"),
            ("invalid_name",
             "select public.settings_save(repeat('x', 81), null, "
             "'Asia/Jakarta', 0, 0);"),
            ("invalid_address",
             "select public.settings_save('OK', repeat('x', 201), "
             "'Asia/Jakarta', 0, 0);"),
            ("invalid_timezone",
             "select public.settings_save('OK', null, 'Mars/Olympus', 0, 0);"),
            ("invalid_tax_rate",
             "select public.settings_save('OK', null, 'Asia/Jakarta', "
             "1.5, 0);"),
            ("invalid_tax_rate",
             "select public.settings_save('OK', null, 'Asia/Jakarta', "
             "-0.1, 0);"),
            ("invalid_service_rate",
             "select public.settings_save('OK', null, 'Asia/Jakarta', 0, "
             "1.2);"),
        ]
        for message, query in cases:
            with self.subTest(message=message, query=query[:60]):
                with self.assertRaisesRegex(AssertionError, message):
                    self.sql(query, role="authenticated",
                             email="operator@mejeng.id")

        stored = json.loads(self.sql(
            "select to_jsonb(b) from business_settings b where id = 1"))
        self.assertEqual(stored, before)


if __name__ == "__main__":
    unittest.main(verbosity=2)

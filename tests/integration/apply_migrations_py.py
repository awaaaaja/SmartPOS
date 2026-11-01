#!/usr/bin/env python3
"""Pengganti apply_migrations.sh untuk lokal (tanpa psql): stub + semua
migrasi berurutan ke DATABASE_URL. Dipakai untuk validasi lokal saja."""
import glob
import os
import sys
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[2]
url = os.environ["DATABASE_URL"]

conn = psycopg2.connect(url)
conn.autocommit = False
cur = conn.cursor()

def apply(path):
    sql = Path(path).read_text()
    try:
        cur.execute(sql)
        conn.commit()
    except Exception as e:
        conn.rollback()
        print(f"GAGAL {path}: {e}")
        sys.exit(1)

apply(ROOT / "tests/integration/supabase_stub.sql")
for f in sorted(glob.glob(str(ROOT / "supabase/migrations/*.sql"))):
    apply(f)
    print("OK", os.path.basename(f))
print("Semua migrasi lulus.")

#!/usr/bin/env bash
# Terapkan seluruh migrasi berurutan ke database target.
# Pakai: DATABASE_URL=postgres://... ./tests/integration/apply_migrations.sh
set -euo pipefail

DB_URL="${DATABASE_URL:?isi DATABASE_URL}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Menyiapkan stub Supabase (hanya untuk Postgres polos/CI)..."
psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$ROOT/tests/integration/supabase_stub.sql"

for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "Menerapkan $(basename "$f")..."
  psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$f"
done

echo "Semua migrasi lulus."

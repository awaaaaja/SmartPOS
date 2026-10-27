# Smart POS — Waroeng MeJeng Kampoeng

MVP satu operator: aplikasi **Flutter Android** (tablet landscape prioritas) untuk kasir
+ **web Vue** untuk menu pelanggan dari QR meja + **Supabase** (Auth, PostgreSQL).
Spesifikasi: `PRD.md` v2.1. Backlog: `Sprints.md` v2.1. Aturan build: `Prompt.md`.
`index.html` hanya referensi layout (palet hijau/emoji/AI di dalamnya sudah digantikan
brand `#930031`, Material Icons, tanpa ML).

## Struktur

```text
apps/pos_flutter/    # aplikasi kasir Flutter (satu operator)
apps/qr_web/         # web Vue menu pelanggan via QR
supabase/migrations/ # skema, RLS, API publik (Postgres authoritative)
supabase/seed/       # fixture DEV berlabel [DEMO]
docs/                # keputusan, kontrak API, log sprint
```

## Menjalankan

### 1. Supabase

```bash
# terapkan migrasi ke proyek (butuh akses CLI/login)
supabase db push --db-url "$SUPABASE_DB_URL"

# fixture DEV saja (berlabel [DEMO])
psql "$SUPABASE_DB_URL" -f supabase/seed/seed_dev.sql
```

Buat **satu akun operator** di Supabase Auth (email & kata sandi), lalu samakan
`business_settings.operator_email` dengan email tersebut. RLS menolak semua
akun lain.

### 2. Aplikasi kasir (Flutter)

```bash
cd apps/pos_flutter
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Tanpa `--dart-define`, aplikasi menampilkan layar konfigurasi (tidak berpura-pura
terkoneksi). Contoh nilai: `apps/pos_flutter/.env.example`.

### 3. Web QR (Vue)

```bash
cd apps/qr_web
cp .env.example .env.local   # isi URL + publishable key
npm install
npm run dev                  # buka http://localhost:5173/?token=DEV-TOKEN
```

## Uji

```bash
cd apps/pos_flutter && flutter analyze && flutter test
cd apps/qr_web && npm run build
```

## Aturan keamanan

- Hanya kunci **publishable/anon** yang boleh masuk Flutter/web.
- `Kredensial.md` berisi rahasia dan sudah di-gitignore; jangan commit.
- Uang disimpan **integer Rupiah**; total/quote dihitung di Postgres, bukan di klien.
- Tidak ada modul Pesanan/Dapur/Pegawai/SaaS/ML pada MVP.

## Kandidat rilis / serah terima

Sprint 06 **PARTIAL, belum siap produksi**: APK berhasil dibangun tetapi unsigned;
retry refund/koreksi stok belum aman dan pengujian Android target belum dilakukan.

- [Changelog, artefak dan batasan](docs/release-notes.md)
- [Setup Supabase, signing, instalasi, SOP dan gate UAT](docs/handover.md)
- [Bukti dan prosedur backup/restore](docs/backup-restore.md)
- [Hasil QA Sprint 06](docs/evidence/sprint06/README.md)

Suite `tests/integration/test_*.py` membutuhkan `OPERATOR_PASSWORD` dari environment
(tidak ada password default). Jalankan hanya di proyek QA yang boleh berisi mutasi
penjualan, master, stok dan biaya; bukan pada database usaha aktif.

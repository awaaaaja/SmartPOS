# Decision Log

Keputusan teknis yang diuji/diuji-review; urutan kebenaran mengikuti `Prompt.md` §1.

## D-01 (2026-10-26) — API bisnis authoritative = fungsi Postgres (bukan FastAPI terpisah)

- **Keputusan:** logika bisnis authoritative (menu publik, quote, checkout, stok)
  diimplementasikan sebagai fungsi Postgres `SECURITY DEFINER` di
  `supabase/migrations/`, dipanggil lewat RPC Supabase.
- **Alasan:** Sprint 01 hanya butuh "API bisnis terproteksi"; transaksi atomik +
  idempotency lebih mudah dijamin dalam satu transaksi DB. Satu implementasi,
  tanpa service tambahan yang harus dijalankan/diawasi.
- **Konsekuensi:** `services/business_api/` tidak dibuat di Sprint 01; jika
  nanti butuh logika di luar Postgres (mis. printer/queue), layanan itu boleh
  dibuat tipis di atas fungsi yang sama.

## D-02 (2026-10-26) — Penanda satu operator = `business_settings.operator_email`

- **Keputusan:** tanpa tabel pegawai/role; `is_operator()` membandingkan email
  JWT sesi dengan satu baris `business_settings.operator_email`.
- **Alasan:** sesuai PRD v2.1 (satu operator, bukan sistem role). Rotasi akun
  cukup mengubah satu nilai config.

## D-03 (2026-10-26) — Token meja disimpan sebagai hash SHA-256

- **Keputusan:** `dining_tables.qr_token_hash = sha256(token)`; token asli tidak
  pernah disimpan, validasi dengan mem-hash input lalu lookup.
- **Alasan:** kebocoran DB tidak langsung membocorkan token QR aktif; rotasi =
  update hash + `token_version`.

## D-04 (2026-10-26) — WIB dihitung manual (UTC+7), bukan paket zona waktu

- **Keputusan:** `formatWib()` menambah 7 jam ke UTC dan memakai nama bulan
  Indonesia statis.
- **Alasan:** deterministik di device dengan zona apa pun, tanpa inisialisasi
  `initializeDateFormatting` dan tanpa dependensi tambahan.

## D-05 (2026-10-26) — Konfigurasi Flutter via `--dart-define`, layar konfigurasi jujur

- **Keputusan:** `SUPABASE_URL` + `SUPABASE_PUBLISHABLE_KEY` masuk lewat
  `--dart-define`; tanpa keduanya aplikasi menampilkan layar petunjuk setup,
  bukan crash atau mode pura-pura nyambung.

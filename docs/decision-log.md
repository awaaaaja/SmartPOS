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

## D-06 (2026-10-30) — Arah ML post-MVP: demand forecasting auto-retrain; MVP hanya agregat deterministik

- **Keputusan:** satu arah ML pasca-MVP = **forecast qty menu per jam/hari
  dengan training ulang otomatis** (fase 0–3, syarat naik fase berbasis jumlah
  data, bukan tanggal). Di MVP hanya dibuat **view agregat deterministik**
  (migrasi `20261030000017_analytics_aggregates.sql`) tanpa model apa pun.
- **Alasan:** PRD §9 menunjuk arah forecast menu/jam ramai sebagai pertimbangan
  post-MVP; semua fitur yang dibutuhkan sudah ada di skema (`sales`,
  `sale_items`, `product_price_history`, `stock_movements`). Anomali kas,
  market basket, harga dinamis, dan churn ditolak/ditunda (alasan lengkap di
  `docs/ml-roadmap.md` §1). Volume data saat ini (75 transaksi dari 3 hari
  aktif, 31 Okt 2026) membuat model apa pun hanya menghafal kebisingan.
- **Konsekuensi:** tidak ada tabel `forecast_runs`, endpoint `/v1/forecasts`,
  halaman `AI Insights`, atau library ML di MVP (PRD §9). Kode ML baru boleh
  masuk setelah amendemen PRD §9 ditulis; prediksi selalu berupa saran yang
  butuh persetujuan operator (PRD baris 69). Detail loop auto-retrain,
  champion/challenger, dan guardrail: `docs/ml-roadmap.md`.

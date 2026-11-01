# Roadmap ML Post-MVP — Demand Forecasting yang Belajar Sendiri

**Status: DOKUMEN KEPUTUSAN post-MVP. Tidak ada kode ML yang dikerjakan di MVP.**

Dokumen ini menjabarkan keputusan D-06 (`docs/decision-log.md`) dan batasan
PRD v2.1 §9: MVP tidak membangun, melatih, menjalankan, atau menampilkan model
ML/AI. Yang ada sekarang hanya **agregat deterministik** (migrasi
`20261030000017_analytics_aggregates.sql`) agar histori siap dilatih nanti.

Dilarang di MVP (PRD §9) dan **tidak dibuat** oleh dokumen ini: halaman
`AI Insights`, endpoint `/v1/forecasts`, tabel `forecast_runs`, paket `ml_api`,
dan library ML di klien.

## 1. Keputusan

**Satu arah: demand forecasting per menu, per jam/hari, dengan training ulang
otomatis.** Angka keluaran = prediksi jumlah terjual, bukan perintah belanja.

| Kandidat | Keputusan | Alasan |
|---|---|---|
| **Forecast qty menu & jam ramai** | **DIPILIH** | PRD §9 sendiri menunjuk arah ini; fitur sudah ada semua di skema (`sales`, `sale_items`, `product_price_history`, `stock_movements`) |
| Anomali kas/refund | DITUNDA | Berguna, tapi sinyalnya kecil di data saat ini (75 transaksi); aturan sederhana (deviasi 3σ harian) sudah cukup tanpa model |
| Rekomendasi menu/upsell (market basket) | DITOLAK | Satu operator, tanpa halaman Pesanan; hasilnya sulit ditindaklanjuti di POS yang sudah padat |
| Harga dinamis/otomatis | DITOLAK | Berisiko pada warung; PRD melarang tindakan otomatis tanpa persetujuan operator |
| Klasifikasi pelanggan/churn | DITOLAK | Tidak ada identitas pelanggan; bertentangan dengan privasi minimal (PRD §10) |

## 2. Data yang tersedia sekarang (tanpa ML)

Lima view hasil migrasi `0017` (semua `security_invoker=true`, RLS tabel dasar
tetap berlaku, grant hanya `authenticated`):

| View | Grain | Dipakai untuk |
|---|---|---|
| `v_sale_item_facts` | 1 baris / item terjual | fitur mentah: `sale_day`, `sale_hour`, `day_of_week`, `hour_of_day`, `qty`, `line_revenue` |
| `v_sales_daily` | 1 baris / hari | total uang, transaksi, pisah `DINE_IN`/`TAKEAWAY`, refund |
| `v_sales_hourly` | 1 baris / jam | pola jam ramai (fitur musiman jam) |
| `v_product_daily` | 1 baris / menu × hari | **target forecasting**; sale `REFUNDED` dikeluarkan |
| `v_stock_usage_daily` | 1 baris / bahan × hari × sumber | menerjemahkan forecast → kebutuhan bahan (RECIPE/PRODUCTION vs PURCHASE/WASTE) |

Catatan jujur:

- Hari/jam dihitung `at time zone 'Asia/Jakarta'` (pola 0011), bukan zona device.
- Uang selalu dihitung per **transaksi**, tidak per item, supaya join ke item
  tidak menggandakan omzet.
- `REFUNDED` dikeluarkan dari agregat menu; **refund sebagian tidak dikurangi**
  di view (jumlah pastinya ada di tabel `refunds`) — masuk daftar pekerjaan
  saat fase 2 dimulai.
- Nama menu di-snapshot per transaksi: rename menu membuat baris terpisah,
  bukan digabung paksa.

## 2b. Kandidat sekunder (terdaftar 1 Nov 2026 — NON-ML / menunggu syarat)

Tiga kandidat dari analisa "HPP & Kalkulator Energi berpengaruh kemana"
didaftarkan agar keputusannya terdokumen, bukan hilang begitu saja.
Status: **A2 & B1 sudah DIIMPLEMENTASIKAN sebagai rekomendasi non-ML**
(RFC `docs/rfc-rekomendasi-hpp-energi.md`, migrasi `0020`); **B2 menunggu
syarat data & amendemen PRD §9** (guardrail §7 masih berlaku penuh).

| ID | Kandidat | Keputusan | Alasan & syarat |
|---|---|---|---|
| A1 | Kebutuhan bahan + dampak HPP dari demand forecasting | **JALUR UTAMA** (Fase 1–2, §5) | Turunan langsung dari forecast qty menu; butuh amendemen PRD §9 sebelum kode model |
| **A2** | **Peringatan HPP** (harga bahan menyimpang dari rata-rata pembelian + dampak per porsi) | **DIIMPLEMENTASIKAN non-ML** (`inv_hpp_alerts`, migrasi `0020`) | Statistik deskriptif murni — tidak butuh model, tidak butuh amendemen; sudah live |
| **B1** | **Koreksi faktor kalkulator energi** (ESTIMATED vs ACTUAL + deviasi + faktor koreksi) | **DIIMPLEMENTASIKAN non-ML** (`exp_energy_calibration`, migrasi `0020`) | Sama: perbandingan dua angka yang sudah ada; deviasi hanya dari jenis dengan tagihan asli |
| **B2** | **Proyeksi energi masa depan** (mis. "bulan depan listrik ± RpX") | **MENUNGGU** — kandidat sekunder | Butuh ≥ 3 bulan tagihan `ACTUAL` tercatat agar musiman bisa dinilai; kalau lolos uji kelayakan §8, masuk Fase 2; tetap wajib amendemen PRD §9 (guardrail §1) sebelum kode model |
| — | Otomasi belanja/harga dari sinyal HPP | **DITOLAK** (tetap) | PRD melarang tindakan otomatis tanpa persetujuan operator; rekomendasi hanya saran, tombol di tangan operator |

Catatan jujur A2/B1: keduanya **bukan ML** — tidak ada training, inferensi,
atau prediksi; hanya agregat SQL. Keberadaannya **tidak membuka** panggung
ML; panggung ML tetap tertutup sampai amendemen tertulis PRD §9 (lihat §7).

## 3. Kesiapan data — syarat naik fase

Ukuran saat ini (dicek langsung ke hosted, 31 Okt 2026): **75 transaksi** dari
**3 hari aktif** (sejak 26 Okt 2026), omzet all-time Rp1.347.598. Dengan volume
itu model apa pun hanya akan menghafal kebisingan, jadi fase 1-3 menunggu syarat
kuantitatif.

| Fase | Syarat minimal | Skor minimal untuk lanjut |
|---|---|---|
| 1 — statistik online | ≥ 300 transaksi dan ≥ 3 minggu histori | MAPE mingguan < baseline "pekan lalu" |
| 2 — gradient boosting | ≥ 1.500 transaksi, ≥ 8–12 minggu, ≥ 6 hari aktif/minggu | WAPE harian < 30% dan mengalahkan baseline musiman |
| 3 — champion/challenger otomatis | ≥ 6 bulan stabil, termasuk ≥ 2 periode promo/harga berubah | WAPE membaik ≥ 5% dibanding fase 2 di rolling 4 minggu |

Syarat ini yang menentukan "kapan", bukan tanggal. Bila syarat belum terpenuhi,
jawaban yang benar adalah **tampilan kosong yang jujur**, bukan angka pura-pura
(sejalan UAT-14).

## 4. Cara "belajar sendiri" dan "berkembang sendiri"

Yang membuat sistem ini mandiri bukan hanya modelnya, melainkan **loop
evaluasi yang menolak perbaikan palsu**:

```
kron harian (GitHub Actions / Supabase Edge Function, cron)
  → baca view agregat (fitur + target)
  → bangun fitur: lag-1/7/14/28, rata-rata bergerak, hari, jam,
    harga dari product_price_history, jenis sajian, hari besar
  → latih model kandidat (challenger)
  → backtest rolling-origin terhadap 4 minggu terakhir
  → BANDINGKAN dengan baseline musiman (naive musiman + EWMA)
  → menang  → tulis model sebagai champion + prediksi ke tabel (auto-promote)
  → kalah  → pertahankan champion / kembali ke baseline, catat alasannya
  → setiap prediksi disimpan bersama tanggal, dan actual-nya dihitung
    besok → skor kualitas mengalir sendiri ke evaluasi berikutnya
  → drift (error melonjak 2× lipat selama 7 hari) → turun kelas otomatis
    ke baseline, panel menampilkan "prediksi dinonaktifkan sementara"
```

Tiga jaminan yang membuatnya boleh dibiarkan jalan sendiri:

1. **Gerbang numerik, bukan optimism model**: kandidat hanya naik kelas bila
   mengalahkan baseline pada backtest jujur (data yang belum pernah dilihat).
2. **Rollback otomatis**: bila champion memburuk, sistem mundur ke baseline
   deterministik yang selalu bisa dihitung ulang di Postgres.
3. **Jejak audit**: setiap promosi/rollback tercatat (pola `audit_events`),
   sehingga keputusan otomatis bisa ditelusuri manusia.

## 5. Rencana per fase

### Fase 0 — sekarang (MVP)
- Tanpa ML. Kumpulkan histori lewat transaksi normal; view `0017` sudah siap.
- Dashboard tetap deskriptif (PRD §9).

### Fase 1 — 0–8 minggu histori
- Model: **exponential smoothing per menu** (Holt-Winters level/trend) dengan
  faktor hari/jam; parameter diupdate **tiap transaksi masuk**.
- Tempat jalan: SQL/pgPL atau lapisan ringan — **tanpa layanan Python**.
- Output: "estimasi kebutuhan bahan besok" sebagai saran, operator menyetujui.

### Fase 2 — ≥ 8–12 minggu histori
- Model: **LightGBM/CatBoost** (fitur kategori hari/libur cocok untuk ini).
- Training harian otomatis lewat cron; hasil ditulis ke tabel prediksi.
- Mulai memakai `product_price_history` (harga berubah → permintaan berubah)
  dan `v_stock_usage_daily` untuk menerjemahkan kebutuhan bahan.
- Baru saat inilah amendemen PRD §9 dibuka (lihat §7).

### Fase 3 — ≥ 6 bulan, auto-evaluation
- Champion/challenger penuh seperti diagram §4, plus monitoring drift per menu,
  kalender hari besar Indonesia sebagai fitur, dan eksperimen terkontrol
  (mis. uji promo: apakah prediksi meleset saat harga turun?).

## 6. Tabel/kontrak masa depan (BELUM dibuat)

Nama-nama di bawah hanya rencana; **tidak ada di repo sekarang** dan tidak boleh
dibuat sebelum amendemen PRD §9 disetujui:

| Tabel | Isi |
|---|---|
| `demand_forecasts` | prediksi per menu × hari × jam + versi model + status (aktif/baseline/berhenti) |
| `forecast_actuals` | pasangan prediksi × aktual + WAPE berjalan |
| `ml_eval_runs` | hasil backtest tiap malam: model, skor, keputusan promosi/rollback |
| `ml_model_registry` | artefak model, hyperparameter, data-range, checksum |

## 7. Guardrail (mengikat, bukan saran)

1. **Amendemen PRD lebih dulu.** Kode ML hanya boleh masuk setelah §9 diubah
   secara tertulis; dokumen ini belum mengubah PRD.
2. **Tidak pernah memesan sendiri.** PRD melarang pembelian bahan otomatis
   tanpa persetujuan operator — prediksi hanya menyusun *saran*, tombol tetap
   di tangan operator.
3. **Label jujur.** Setiap angka prediksi ditandai "estimasi, bukan jaminan";
   saat sistem gagal, tampilkan status nonaktif, bukan angka lama.
4. **Tanpa ML di klien.** Tidak ada library ML di Flutter/QR web; klien hanya
   membaca angka hasil server.
5. **Privasi.** Hanya agregat menu/jam; tanpa identitas pelanggan (PRD §10).
6. **Determinisme saat gagal.** Jika pipeline cron mati, tampilan terdegradasi
   ke baseline musiman yang bisa dihitung Postgres — bukan kosong-menipu.
7. **Audit setiap keputusan otomatis** promosi/rollback/drift.

> **Status amendemen (1 Nov 2026): PRD §9 BELUM diubah.** Guardrail ini masih
> berlaku penuh. Dua rekomendasi **non-ML** (peringatan HPP `inv_hpp_alerts`,
> kalibrasi energi `exp_energy_calibration`, migrasi `0020`) **tidak memakai
> model, training, atau prediksi** — murni statistik deskriptif SQL — sehingga
> tidak dihitung sebagai "kode ML" dan tidak butuh amendemen. Panggung ML
> (kandidat A1 jalur utama & B2 sekunder) tetap tertutup sampai §9 diamendemen
> secara tertulis.

## 8. Uji kelayakan (dijalankan pertama kali saat syarat §3 terpenuhi)

1. Ambil 4 minggu terakhir, lakukan **rolling-origin**: latih 3 minggu →
   uji 1 minggu, geser, ulangi.
2. Bandingkan tiga kandidat: (a) baseline musiman naif, (b) EWMA/Holt-Winters,
   (c) gradient boosting.
3. Metrik: **WAPE** (utama, tahan terhadap menu dengan volume kecil) dan
   MAPE per menu hanya untuk menu dengan ≥ 20 penjualan.
4. Lolos gerbang hanya bila (b) atau (c) mengalahkan (a) secara konsisten di
   ≥ 3 dari 4 lipatan. Kalau tidak: **tidak diluncurkan**, catat alasan di
   dokumen ini, ulangi tiga bulan kemudian.

## 9. Risiko dan mitigasi

| Risiko | Mitigasi |
|---|---|
| Data sangat sedikit (75 transaksi, 3 hari aktif) | Fase 1 memakai pooling antar menu + shrinkage ke kategori; syarat §3 menahan fase 2 |
| Menu/promo berubah → distribusi bergeser | Fitur harga dari `product_price_history`; drift monitor menurunkan ke baseline |
| Hari besar/Libur sekolah tak terlihat data | Kalender hari besar Indonesia masuk fitur di fase 3 |
| Pipeline mati/lupa | Status "prediksi tidak tersedia" yang jujur + baseline selalu tersedia |
| Overfit ke satu menu laris | WAPE agregat + minimum penjualan sebelum MAPE per menu dipakai |
| Menambah biaya operasional | Fase 1 nol infra (SQL); fase 2-3 cukup cron beberapa menit/hari di GitHub Actions yang sudah ada |

## 10. Referensi

- `PRD.md` §9 (Dashboard Aktif, Bukan Machine Learning) dan larangan pembelian
  otomatis.
- `docs/decision-log.md` D-06 (keputusan arah ML) dan D-04 (WIB).
- `docs/api-contracts.md` bagian view agregat.
- `supabase/migrations/20261030000017_analytics_aggregates.sql` (satu-satunya
  artefak "persiapan ML" yang ada di MVP).
- `tests/integration/test_analytics_views.py` (8 pemeriksaan view).

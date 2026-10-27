# Sprint Log

## Sprint 06 — Polishing, QA, keamanan dan kandidat build
Tanggal: 27 Oktober 2026
Target/tiket: S06-01 … S06-10
Status: **PARTIAL / RELEASE BLOCKED** — jangan menyatakan siap produksi.

### Per tiket
| Tiket | Status | Hasil / yang belum terbukti |
|---|---|---|
| S06-01 | PARTIAL | Audit 13 layar × 2 viewport × 3 state = 78 tes; perbaikan header/kartu overflow tujuh modul, POS tablet dua kolom, keranjang HP live dan form pembayaran scroll saat keyboard. Belum seluruh modal/populated state/keyboard di Android. |
| S06-02 | PASS backend & klien QA | Regresi POS 77, inventori 57, QR 37, operasional 41 = **212 PASS, 0 FAIL** diulang terhadap hosted setelah `0014`. Audit semua RPC uang/stok selesai; empat celah lanjutan ditutup. 15 SQL + 155 Flutter lulus; smoke Chrome lost-response → reload → replay aman. UAT jaringan di tablet belum. |
| S06-03 | PARTIAL | 29 probe hosted: 25 tabel privat anon tertutup + injection token + RPC internal ditolak. Non-operator ditolak di staging lokal. Scan pattern source/APK tidak menemukan secret server; password tes default dihapus. Rotasi password lama dan pemeriksaan riwayat sebelum distribusi masih wajib. |
| S06-04 | PARTIAL | Dump privat + restore lokal 25 tabel/checksum dan 23 policy RLS; total uang cocok. Auth/Storage penuh, cloud staging, retensi terenkripsi dan crash-reporting release belum lulus. |
| S06-05 | PARTIAL | Smoke Chrome manual sale #57 dan QR Q00114 → sale #58 lulus; subtotal 7.000, pajak 525, layanan 175, total 7.700, bayar 10.000, kembali 2.300. Bukan pengujian tablet target. |
| S06-06 | PARTIAL | 1.000 produk memakai lazy list; metrik debug/widget dan latensi hosted dicatat. Belum profil native/FPS, tidak mengklaim UI bebas freeze pada tablet. |
| S06-07 | DEFERRED | Printer ESC/POS/Bluetooth menunggu tipe perangkat; tidak menambah driver/fitur cetak fiktif. |
| S06-08 | NOT IN SCOPE | Online-only, tanpa SQLite outbox. Operator harus mengetahui tidak ada sinkronisasi offline. |
| S06-09 | PARTIAL | APK release terbaru memuat `0013`–`0014`; versi 1.0.0+1, 58.281.930 byte. **Unsigned**, verifikasi signature exit 1, belum dipasang. AAB tidak diperlukan untuk QA sideload dan belum dibangun. |
| S06-10 | PARTIAL | Changelog, instalasi/signing, setup Supabase, SOP dan checklist UAT tersedia. Latihan dan persetujuan operator belum dilakukan. |

### Perbaikan yang sudah diterapkan
- Test lama mengasumsikan pajak nol; kini total/nominal pembayaran mengikuti
  pajak/layanan aktif, tanpa mengubah tarif usaha demi tes.
- Header meja/katalog/stok/resep/pembelian dapat membungkus; hasil energi tidak
  melebar; kartu laporan mengikuti tinggi konten, bukan aspect ratio tetap.
- Breakpoint konten POS memperhitungkan sidebar tablet; HP memantau provider
  keranjang di dalam modal sehingga perubahan jumlah masuk quote pembayaran.
- Form pembayaran scroll saat keyboard, dropdown metode tidak overflow.
- Pengaturan membaca nama/alamat/zona waktu/tarif Supabase (read-only);
  dashboard tidak lagi menjanjikan data di sprint lama.
- Default password operator tidak lagi tertanam di empat suite integrasi;
  `OPERATOR_PASSWORD` wajib dari environment. Riwayat Git tidak ditulis ulang.
- Release tidak memakai debug signing; empat env `MEJENG_*` dibaca Gradle;
  tanpa keystore build **unsigned**, bukan build siap distribusi.
- Lint lama dibersihkan; CSV browser memakai dependency `web` yang sebelumnya
  sudah terpasang transitif. Tidak menambah dependency printer/offline/analytics.

### Hasil dan bukti
- `flutter analyze`: **No issues found**; `flutter test`: **134/134** saat audit
  awal, **148/148** setelah `0013`, kini **155/155** setelah lanjutan `0014`.
  Log di `docs/evidence/sprint06/`.
- 212 pemeriksaan integrasi dijalankan ulang terhadap hosted **setelah** migrasi
  `0014`: **212 PASS, 0 FAIL** (POS 77, inventori 57, QR 37, operasional 41).
  Suite tetap memerlukan `OPERATOR_PASSWORD` environment.
- Flutter web release dan Vue build berhasil. Delapan screenshot browser
  1024×768 / 390×844, angka smoke dicocokkan DB (`browser-smoke.json`).
  Meja QA dinonaktifkan sesudah pengujian; dua sale QA tetap historis, tidak dihapus.
- Klik ekspor CSV web menghasilkan Blob 1.023 byte, UTF-8 BOM, baris integer
  `Penjualan,Net sales,954898` cocok layar (`csv-browser.json`).
- Backup bisnis/auth.users privat di `/tmp/opencode/smart-pos-backups/`,
  tidak masuk Git. Restore subset bisnis di database lokal terisolasi lulus;
  snapshot **sebelum** dua sale smoke. Batasan ada di `docs/backup-restore.md`.
- Latensi median lima request: quote **814 ms**, dashboard **1.231 ms**,
  laporan **2.165 ms**, katalog **1.123 ms**; maksimum dashboard **6.047 ms**
  termasuk retry jaringan. Dua reset transport dicatat, bukan disembunyikan.
- Fixture 1.000 menu: render awal **5.227 ms**, termasuk scroll **7.114 ms**
  dalam harness debug saat pekerjaan build lain berjalan; bukan benchmark native
  atau angka FPS. Tidak menambah cache spekulatif berdasarkan angka ini.
- SHA-256/path APK dan scan pola sensitif: `android-build.json`.

### Blocker yang ditemukan: K06-01 — retry menggandakan mutasi (DIPERBAIKI)
Di staging lokal hasil restore, dua panggilan `pos_refund(..., 100, ...)`
identik menghasilkan total refund Rp200; dua koreksi stok +1 menghasilkan +2.
Reproduksi dibungkus `BEGIN/ROLLBACK`; uang/stok hosted tidak diubah.
API tersebut tidak punya kunci idempotensi. **Tombol busy/guard UI tidak cukup**
untuk timeout setelah server commit. Bukti awal `retry-gap.json`.

**Perbaikan (27 Okt 2026):**
- Migrasi `20261027000013_mutation_retry.sql` — tabel `mutation_requests`
  (RLS aktif, 0 policy, tanpa SELECT untuk anon/authenticated), wrapper
  `pos_refund(4 arg)` & `inv_adjust_stock(6 arg)` dengan `p_idempotency_key`
  wajib, advisory lock per key + PK, cek payload identik, respons atomik;
  implementasi lama direname `*_once` dan dicabut grant-nya. Koreksi negatif
  `ADJUSTMENT` kini divalidasi lewat magnitudo (bug sampingan yang ditemukan
  saat menulis tes).
- Klien: `lib/core/mutation_retry.dart` menyimpan key+payload di
  `SharedPreferencesAsync` **sebelum** RPC, memakainya ulang saat timeout/buka
  ulang, menolak payload berbeda, dan hanya menghapus entri setelah konfirmasi
  bisnis. Form riwayat dan form koreksi/waste tidak ditutup saat submit, input
  terkunci saat pending, tombol berganti "Ulangi … yang sama".
- Bukti `evidence/sprint06/retry-fix.json`: replay hosted dalam
  `BEGIN/ROLLBACK` → refund **+100**, stok **+1**, `idempotent_replay` benar,
  payload beda → `idempotency_key_conflict`, sisa baris 0; probe anon 401 pada
  kedua RPC dan tabel; 9 tes SQL lokal; 148 tes Flutter; analyzer 0 issue.
- **Migrasi sudah diterapkan ke hosted** (`supabase db push`); regresi 4 suite
  terhadap hosted setelah migrasi: **212 PASS, 0 FAIL**.
- Status di atas adalah hasil `0013`; audit lanjutan dan empat fix sisa selesai
  di `0014` berikut. Distribusi klien dan UAT perangkat target tetap belum.

### Lanjutan K06-01 — empat RPC sisa (SELESAI backend/klien QA)
- Audit menemukan retry menggandakan PO/stok, batch/pemakaian bahan, CREATE biaya,
  dan estimasi energi/expense. `inv_receive_purchase` dan buka/tutup kas sudah
  memakai lock/guard status; `cost_allocate` memakai upsert, tidak menggandakan
  alokasi. Checkout/QR mempunyai key sendiri; master bahan/resep bukan ledger.
- Migrasi `20261027000014_mutation_retry_rest.sql` memperluas `mutation_requests`,
  menutup empat implementasi `*_once` dari klien, dan memakai helper internal
  `mutation_run_once` (tanpa grant klien). Key wajib 8–128 char, advisory lock,
  payload conflict dan respons atomik; data historis tidak disentuh.
- UPDATE `exp_save` tetap tanpa key/cache (penetapan nilai, bukan INSERT),
  sehingga edit berikutnya tidak terkunci. Jalur ini juga memeriksa operator;
  tes non-operator menolak UPDATE sebelum efek.
- Repository Flutter mengirim key untuk keempat alur; form memulihkan payload
  terkunci setelah timeout/relaunch. Pembandingan nested list/map pembelian kini
  memakai `DeepCollectionEquality` dari `collection` yang sudah terpasang.
  `http` yang sudah terpasang dinyatakan sebagai dev dependency untuk tes RPC
  sebenarnya dengan transport palsu. Tidak menambah fitur/abstraksi outbox.
- Tidak menambah buang-pending: replay lama harus dikonfirmasi sebelum niat baru.
  Storage hilang/rusak tetap membutuhkan rekonsiliasi, bukan clear data aplikasi.
- **Hosted:** backup definisi privat `pre-0014-functions.sql`, dry-run dan push
  `0014` lulus. Probe `BEGIN/ROLLBACK`: PO/batch/biaya/energi masing-masing satu
  efek, saldo 100+1−10=91, energi Rp2.880, empat konflik ditolak, empat cache;
  fixture/key tersisa 0 setelah rollback (sequence ID boleh maju). Anon keempat
  RPC 401; helper/legacy tanpa grant klien; tabel RLS aktif, policy 0.
- **Tes:** 15 SQL lokal lulus (replay, 8 concurrent request, konflik, validasi,
  rollback, izin); **155/155 Flutter**, analyzer 0 issue. Lima widget case baru
  menguji repository nyata/serialisasi RPC + transport mock: purchase, batch,
  expense, listrik, LPG; satu tes edit expense tanpa key dan satu nested equality.
  Regresi hosted setelah migrasi: **212 PASS, 0 FAIL**.
- **Chrome release:** respons energi sukses sengaja dijatuhkan; form pending
  terkunci, reload/reopen pada 390×844 memulihkan isian, retry memakai key lama
  dan `idempotent_replay=true`. DB tetap estimate #22/expense #42 satu baris,
  Rp2.880 ESTIMATED, pending lokal bersih. Satu pasangan data QA dipertahankan
  sebagai histori audit, bukan dihapus. Tiga screenshot tambahan (bukan Android).
- **Build:** web 164,4 dtk dan APK 179,9 dtk lulus. APK 58.281.930 byte, SHA-256
  `6afbfbb6cf3d36763bdcfd512113304a2f0e0aabb60cd0c9014fc3725d0a7289`.
  Empat label retry terverifikasi di `libapp.so`. Masih **UNSIGNED**,
  `apksigner verify` exit 1 (`Missing META-INF/MANIFEST.MF`).
- Bukti terbaru: `evidence/sprint06/retry-rest-fix.json`; tidak ada Git push atau
  rilis produksi. Klien lama tanpa key gagal tertutup setelah migrasi.

### Paket serah terima / gate tersisa
`docs/release-notes.md`, `docs/handover.md`, `docs/backup-restore.md`,
`docs/evidence/sprint06/README.md`. K06-01 backend/klien QA selesai. Gate tersisa:
signing/instalasi dan distribusi klien baru (K06-02), Android target/manual operator
(K06-03), rotasi password lama (K06-05), pemulihan Supabase lengkap (K06-04)
dan hosting QR permanen (K06-06). Tidak ada push/release produksi. S01-08 tetap
menunggu remote GitHub, bukan diklaim hijau.
`graphify update .` selesai; warning parser SQL belum terpasang dan JSON evidence
tanpa node dicatat, tidak disamakan dengan kegagalan tes aplikasi.

## Sprint 05 — Biaya Operasional, Kalkulator, Kas dan Laporan
Tanggal: 27 Oktober 2026
Target/tiket: S05-01 … S05-09
Status: **DONE** — semua tiket lulus dengan bukti nyata (migrasi + RPC Supabase asli, 41 integration test, Flutter 53 test, build web E2E di Chrome)

### Yang dibangun
- [x] **S05-01** Kalkulator energi: `energy_page.dart` — tab Listrik/LPG;
  pratinjau live `kWh = (W × jam × load% ÷ 100) ÷ 1000` dan
  `biaya_LPG = (isi_ulang ÷ jam_efektif) × jam_batch` + biaya/porsi;
  server menghitung ulang rumus saat menyimpan.
- [x] **S05-02** Tabel `equipment`/`energy_estimates`/`expenses`/
  `cost_allocations` di migrasi
  `supabase/migrations/20261027000012_operating_cost.sql` (terpush);
  estimasi selalu menjadi expense `ESTIMATED`, tidak pernah otomatis aktual.
- [x] **S05-03** Biaya operasional: `expenses_page.dart` — input LISTRIK/LPG/
  AIR/KEMASAN/SEWA/INTERNET/LAINNYA, penanda ESTIMASI/AKTUAL terpisah di
  list & laporan, URL bukti opsional, ubah tanggal.
- [x] **S05-04** Alokasi biaya `cost_allocate` — server menolak
  `allocation_exceeds_source` (juga saat nominal sumber diperkecil di bawah
  alokasi lama); sheet alokasi per expense.
- [x] **S05-05** Kas Shift `cash_page.dart` + RPC `cash_shift_open/status/
  close` — hanya payment CASH menambah expected (transfer/QRIS
  dikecualikan server); selisih `actual − expected` dihitung server;
  partial unique index satu shift OPEN.
- [x] **S05-06** Dashboard detail: 4 kartu dari `pos_reports` hari ini
  (biaya bahan/HPP estimasi, biaya aktual, overhead estimasi, estimasi
  hasil operasi) dengan label jujur "bukan laba bersih".
- [x] **S05-07** Laporan `reports_page.dart` + RPC `pos_reports(p_from,p_to)`:
  filter tanggal, tren omzet harian, menu terlaris, biaya per kategori
  (aktual vs estimasi terpisah), refund mengurangi net sales, HPP bahan
  dari resep aktif × unit_cost (dilabeli estimasi).
- [x] **S05-08** Ekspor CSV (`buildReportCsv` + unduhan browser via
  conditional import): BOM UTF-8, angka integer polos tanpa pemisah ribuan
  agar makna tidak berubah di lembar kerja.
- [x] **S05-09** Test: `tests/integration/test_operating_cost.py` (41 PASS)
  + `test/features/operating_cost_test.dart` (11 test: rumus listrik/LPG/
  per porsi, halaman, CSV, margin) → UAT-09–11 lulus.

### Verifikasi
- `supabase db push` migrasi `20261027000012_operating_cost.sql` → "Finished".
- `python3 tests/integration/test_operating_cost.py` → **41 PASS, 0 FAIL**
  (rumus 800W×3j×80%×Rp1.500 = 1,92 kWh / Rp 2.880; LPG 22.000/20×2,5 =
  Rp 2.750; alokasi tepat=sumber OK, +1 ditolak, shrink sumber ditolak;
  kas 100.000 + tunai, transfer dikecualikan, selisih −500; laporan =
  hitungan DB; anon 401/403).
- `flutter analyze` → 0 error (sisa 21 info dari file lama Sprint 01–04).
- `flutter test` → **53/53 lulus** (11 baru Sprint 05 + regresi shell test
  diperbarui: halaman Biaya Operasional kini halaman nyata, bukan placeholder).
- `flutter build web --release` → ✓ (93,8 dtk) dengan dart-define produksi.
- `npm run build` (apps/qr_web) → ✓ built in 2,88 dtk.

### Bukti E2E (Chrome, build web final)
| # | File | Membuktikan |
|---|---|---|
| 1 | `01_dashboard_awal.png` | S05-06: kartu HPP/biaya aktual/overhead estimasi/estimasi hasil operasi hari ini |
| 2 | `02_kalkulator_listrik_pratinjau.png` | Demo wajib 800W×3j×80%×Rp1.500 → **1,920 kWh / Rp 2.880 / Rp 288 per porsi** |
| 3 | `03_kalkulator_disimpan_estimasi.png` | Simpan → "Tersimpan … ESTIMATED (nilai server)" |
| 4 | `04_kalkulator_lpg_pratinjau.png` | LPG 22.000/20j × 2,5j → Rp 1.100/jam, Rp 2.750 batch, Rp 275/porsi |
| 5 | `05_biaya_estimasi_vs_aktual.png` | Listrik/LPG "dari kalkulator" ESTIMASI; sewa AKTUAL — chip & ikon terpisah |
| 6 | `06_alokasi_ditolak_melebihi_sumber.png` | Sumber Rp 1.500.000 teralokasi penuh; +Rp 500.000 → snackbar "Total alokasi melebihi nominal biaya" |
| 7 | `07_kas_shift_dibuka.png` | Shift dibuka kas awal Rp 100.000 |
| 8 | `08_kas_expected_hanya_tunai.png` | Tunai net Rp 20.000 → expected Rp 120.000; transfer Rp 20.000 **tidak** menambah kas fisik |
| 9 | `09_kas_tutup_selisih.png` | Tutup kas; DB: expected 120.000, actual 119.500, **variance −500** |
| 10 | `10_laporan_penuh.png` | Net sales Rp 671.000 / refund Rp 171.000 / tren 2 hari / menu terlaris / biaya per kategori (AIR, LISTRIK, LPG, SEWA) aktual vs estimasi / catatan jujur |
| 11 | `11_laporan_export.csv` | CSV terunduh & terbuka: angka integer polos, nilai = screenshot laporan |

### Gate S05
- [x] **UAT-09** Kalkulator listrik & LPG: rumus benar (client preview =
  server recompute: 1,92 kWh & Rp 2.880; LPG Rp 2.750); estimasi vs aktual
  dipisah di list, laporan, dan DB (`kind` ESTIMATED/ACTUAL).
- [x] **UAT-10** Alokasi: total per sumber ≤ nominal (tepat = sumber OK,
  +1 ditolak server; mengecilkan sumber di bawah alokasi lama ditolak);
  laporan `allocated_total` = DB.
- [x] **UAT-11** Tutup kas: hanya CASH menambah expected (transfer
  dikecualikan); selisih −500 = actual 119.500 − expected 120.000, tercatat
  di `cash_shifts` + audit event.

### Temuan dan perbaikan saat pengujian
- Masalah: pesan penolakan alokasi tampil "Terjadi kesalahan tak terduga".
  Penyeban: `allocate()` melakukan cast `rpc(...) as Future<Map<…>>` —
  Future<dynamic> melempar TypeError sebelum error server terbaca.
  Perbaikan: `await` dulu, cast hasilnya (`operating_repository.dart`);
  rebuild web → snackbar "Total alokasi melebihi nominal biaya" benar.
- Masalah: test "keterangan < 3 huruf" gagal (200).
  Penyebab: test memakai "singkat" (7 huruf) — lolos validasi ≥3.
  Perbaikan: test diperbaiki ("ab"); kode benar.
- Masalah: `shell_test.dart` mengharapkan placeholder "Menyusul: Sprint 05".
  Perbaikan: ekspektasi diubah ke halaman nyata (tombol "Biaya Baru").
- Catatan otomasi Chrome: Flutter web butuh klik `flt-semantics-placeholder`
  setelah reload agar snapshot a11y tersedia; snackbar 4 dtk tertangkap
  dengan klik → screenshot langsung beruntun.

### Sisa pekerjaan / risiko
- Pembuktian kas tutup selisih pada layar memakai nilai DB (snackbar
  terlewat saat itu); angka variance −500 terverifikasi langsung dari
  `cash_shifts`.
- Android fisik belum diuji untuk Sprint 05 (perangkat tidak tersedia);
  build web + 53 widget/unit test menjadi pengganti sementara.
- S01-08 (GitHub Actions) masih menunggu remote GitHub.

## Sprint 04 — Stok, Pembelian, Resep, HPP
Tanggal: 27 Oktober 2026
Target/tiket: S04-01 … S04-09
Status: **DONE** — semua tiket lulus dengan bukti nyata (migrasi + RPC Supabase asli, 3 suite integration test penuh, Flutter 42 test, web build di Chrome); pengujian perangkat Android ditunda (perangkat tidak tersedia)

### Yang dibangun
- [x] **S04-01** Master bahan + satuan dasar: migrasi
  `20261026000010_inventory.sql` — tabel `ingredients` (satuan dasar hanya
  g/ml/pcs, qty `numeric`, `reorder_level`, `unit_cost`), fungsi
  `inv_to_base` (konversi **kg↔g / L↔ml di server**), `inv_save_ingredient`
  (nama/batas/biaya divalidasi; satuan dasar terkunci setelah dibuat).
- [x] **S04-02** UI `Stok Bahan` (`stock_page.dart`): daftar + pencarian
  (`ilike`), chip status **HABIS / DI BAWAH MINIMUM** (jujur, tanpa angka
  palsu), tambah/ubah bahan, dialog **Koreksi / Waste wajib alasan ≥3 huruf**
  (`inv_adjust_stock` → selalu tulis ledger), sheet riwayat mutasi per bahan.
- [x] **S04-03** Form `Pembelian` (`purchases_page.dart`): supplier opsional,
  tanggal, multi-baris bahan+qty+total, status Terima/Pesanan; daftar dengan
  chip DITERIMA/PESANAN + tombol **Terima** berkonfirmasi.
  Server `inv_create_purchase`/`inv_receive_purchase`: saldo & `unit_cost`
  (harga terakhir per satuan dasar) bertambah **tepat sekali** (guard status
  `purchase_already_received`).
- [x] **S04-04** UI `Resep & HPP` (`recipes_page.dart`): pilih menu →
  **HPP per porsi = Σ(qty × unit_cost) ÷ yield** dari versi resep aktif
  (`inv_hpp`), tabel biaya per bahan, **margin hanya dari komponen berdata**
  (harga jual − HPP), riwayat versi (versi lama tidak dihapus), simpan resep
  selalu jadi versi baru (`inv_save_recipe`).
- [x] **S04-05** `recipe_versions`/`recipe_items` (versi aktif) +
  `stock_movements` **append-only**: trigger menolak UPDATE/DELETE, RLS
  SELECT-only operator — riwayat biaya/mutasi telusur.
- [x] **S04-06** Posting pemakaian tepat sekali: trigger
  `AFTER INSERT ON payments` → `inv_post_sale_usage` (1 baris ledger per
  bahan per sale; penjaga defensif: skip bila mutasi `RECIPE` dengan
  `ref = sale_id` sudah ada → retry checkout tidak menggandakan mutasi).
- [x] **S04-07** Pengecualian jujur: menu **tanpa resep aktif = tanpa klaim
  stok** (`has_recipe=false` → UI "resep belum ada"); `products.stock_mode`
  **BATCH** (gorengan) dipotong saat `inv_produce_batch`, bukan saat jual;
  `insufficient_stock` (P0001) **merollback sale** (UAT-06); refund tidak
  otomatis restock.
- [x] **S04-08** Margin per menu + status stok minimum + mutasi terakhir
  (sheet per bahan) — hanya memakai komponen yang ada datanya.
- [x] **S04-09** Test: `tests/integration/test_inventory.py` (57
  pemeriksaan: konversi satuan, penerimaan sekali, HPP, potong bahan sekali,
  retry idempoten, rollback, batch, waste/koreksi beralasan, ledger
  append-only, anon ditolak) + regresi penuh + widget test Flutter baru.
- [x] **Perbaikan di luar tiket (bug nyata saat uji):**
  migrasi `20261027000011_dashboard_tz_fix.sql` — `pos_dashboard_summary`
  membandingkan `timestamptz` dengan timestamp naive (dianggap UTC) sehingga
  batas "hari ini" bergeser 7 jam (omzet hari baru belum masuk sebelum
  07:00 WIB).

### Verifikasi
| Pengujian | Perintah/langkah | Hasil | Bukti |
|---|---|---|---|
| Analyze/lint | `flutter analyze` | **PASS** | 0 error/warning (17 info `unnecessary_underscores`, pola lama) |
| Unit/widget Flutter | `flutter test` | **PASS** | **42/42** (5 baru halaman inventori + 3 baru error mapper `P0001`) |
| Migrasi | `supabase db push` | **PASS** | `0010_inventory`, `0011_dashboard_tz_fix` "Finished" |
| Uji REST inventori | `python3 tests/integration/test_inventory.py` | **PASS** | **57 PASS, 0 FAIL** |
| Regresi POS | `python3 tests/integration/test_pos_api.py` | **PASS** | **77 PASS, 0 FAIL** (23+ skenario uang) |
| Regresi QR draft | `python3 tests/integration/test_qr_drafts.py` | **PASS** | **37 PASS, 0 FAIL** |
| Build web POS | `flutter build web --release --dart-define=…` | **PASS** | `✓ Built build/web` |
| Build web QR | `npm run build` (apps/qr_web) | **PASS** | `✓ built in 12.54s`, dist 299 kB |
| Buktian UI end-to-end (Chrome) | tablet 1280×800 | **PASS** | screenshot `docs/evidence/sprint04/` (lihat di bawah) |

### Bukti E2E (Chrome, build web final, tablet 1280×800)
| # | Skenario | Hasil nyata | File |
|---|---|---|---|
| 01 | Dashboard omzet hari ini | **Rp 199.000 / 7 transaksi final** — batas hari benar setelah fix zona waktu | `01-dashboard-omzet-hari-ini.png` |
| 02 | Daftar stok + status | Urutan A→Z (fix `postgrest-dart` default descending), chip HABIS/DI BAWAH MINIMUM, "Bawang" tampil pertama | `02-stok-daftar-status-minimum.png` |
| 03 | Tambah bahan baru | "Cabai Rawit Uji Sprint04" tersimpan (min 50 g, Rp 1.500/g) — verifikasi REST id 16 | `03-bahan-baru-tersimpan.png` |
| 04 | Form pembelian (Pesanan) | Bawang 2.000 g total **Rp 40.000** (fix form: total baris tanpa × qty) | `04-pembelian-form-pesanan.png` |
| 05 | Daftar pembelian | PO **#13 PESANAN** Toko Bumbu Kampoeng tampil teratas | `05-pembelian-pesanan-list.png` |
| 06 | Konfirmasi terima | Dialog "Terima pembelian #13?" + penjaga penerimaan ganda | `06-konfirmasi-terima-pembelian.png` |
| 07 | Penerimaan | Bawang 0 → **2.000 g**, `unit_cost` 0 → **Rp 20/g**, PO RECEIVED | `07-pembelian-diterima-stok-plus-1x.png` |
| 08 | Ledger pembelian | Sheet mutasi: "Penerimaan po:13 **PURCHASE +2.000 g** sisa 2.000" — 1 baris (fix `Consumer` watch di sheet) | `08-riwayat-mutasi-purchase-ledger.png` |
| 09 | Menu tanpa resep | MENU-TANPA-RESEP-BEFBB5 → status **"resep belum ada"** + penjawan tanpa klaim stok | `09-resep-belum-ada.png` |
| 10 | HPP + versi resep | MENU-RESEP-BEFBB5: HPP **Rp 1.550/ponsi** (v3, yield 2, Σ Rp 3.100), margin Rp 18.450 (komponen berdata), riwayat **v1–v3** | `10-hpp-versi-aktif.png` |
| 11 | Checkout POS | Struk **MJ-261027-0029** Rp 20.000, 1× MENU-RESEP-BEFBB5, CASH | `11-pos-checkout-struk.png` |
| 12 | Mutasi resep terposting | Ledger TEPUNG: "Pemakaian resep MJ-261027-0029 **RECIPE −100 g** sisa 375" (1 baris/bahan, tak dobel) | `12-mutasi-recipe-sale.png` |
| 13 | Waste beralasan | Dialog Waste 25 g + alasan "Jatuh saat pengangkutan" (wajib ≥3 huruf) | `13-waste-beralasan-form.png` |
| 14 | Ledger waste | "Waste: Jatuh saat pengangkutan **WASTE −25 g** sisa 1.975" | `14-waste-ledger.png` |

Verifikasi REST setelah checkout: sale 29 → tepat **2 baris** mutasi RECIPE
(TEPUNG −100 g, SUSU −50 ml; batch yield 2 = per porsi), saldo 475→375 g dan
1.900→1.850 ml.

**Retry idempoten** (`/tmp/opencode/verify_s04_retry.py`, key sama 2×):
checkout pertama `sale_id: 30, idempotent_replay: false` → retry
`sale_id: 30, idempotent_replay: **true**` → mutasi RECIPE sale 30 tetap
**2 baris** (tidak gandakan).

### Gate S04
- [x] Konversi Kg↔g / L↔ml lulus — `inv_to_base` di server (57 pemeriksaan `test_inventory.py`).
- [x] Perubahan tulis ledger — semua mutasi via `inv_post_movement` (append-only, trigger tolak UPDATE/DELETE).
- [x] Saldo + tepat sekali saat diterima — PO #13: 1 baris `PURCHASE`, guard `purchase_already_received`.
- [x] Formula HPP sesuai versi resep + `unit_cost` — UI Rp 1.550 = (200×13 + 100×5) ÷ 2, versi aktif v3.
- [x] Dua retry checkout tidak gandakan bahan — key sama → sale sama (30), ledger tetap 2 baris.
- [x] Tidak otomatis klaim stok akurat untuk menu tanpa resep — "resep belum ada", tanpa mutasi RECIPE.
- [x] Margin hanya komponen berdata — margin = harga jual − HPP resep aktif; menu tanpa resep tanpa angka HPP/margin.

### Temuan dan perbaikan saat pengujian
- **Zona waktu dashboard**: `pos_dashboard_summary` membandingkan `timestamptz` dengan timestamp naive → batas hari bergeser 7 jam; diperbaiki migrasi `20261027000011_dashboard_tz_fix.sql` (ter-push, omzet hari ini benar).
- **Urutan daftar Z→A**: `postgrest-dart` default `ascending=false` (kebalikan SQL) → item terakhir tidak terbangun di viewport; diperbaiki `ascending: true` pada daftar bahan & menu resep.
- **Total form pembelian Rp 80.000.000**: form mengalikan qty × `total_price` padahal server memakai total baris; diperbaiki `lineTotal` tanpa perkalian qty.
- **Sheet riwayat mutasi loading permanen**: `ref.watch` dari builder modal bottom sheet tidak subscribe → data 200 OK tapi tak pernah tampil; dibungkus `Consumer` (bukti screenshot 08/12/14).
- **Input waste**: kontrak `inv_adjust_stock` WASTE = qty **positif** (jumlah hilang; server membalik `-abs`) — sama seperti `test_inventory.py`; input negatif ditolak `invalid_qty`.

## Sprint 03 — Pesanan QR Pelanggan (Draft → Keranjang POS → Bayar)
Tanggal: 26 Oktober 2026
Target/tiket: S03-01 … S03-09
Status: **DONE** — semua tiket lulus dengan bukti nyata (Supabase asli, web build di Chrome, dua "HP" paralel lewat HTTPS aktual via tunnel cloudflared); pengujian perangkat Android ditunda (perangkat tidak tersedia)

### Yang dibangun
- [x] **S03-01** Pengaturan meja + QR URL HTTPS:
  migrasi `20261026000009_table_qr_api.sql` (`qr_create_table` /
  `qr_rotate_token`, token 16 byte acak dari `gen_random_bytes`, plaintext
  hanya dikembalikan sekali, tersimpan sebagai hash SHA-256 — D-03);
  `tables_repository.dart` + `qr_page.dart` (daftar meja, switch
  aktif/nonaktif, rotasi token, dialog QR `qr_flutter` + URL selectable +
  salin; pesan jujur bila `QR_WEB_URL` kosong/non-HTTPS).
- [x] **S03-02** Web Vue QR pelanggan (`apps/qr_web`): `App.vue` +
  `style.css` ditulis ulang — menu publik per kategori, sheet varian
  (min/max modifier + catatan), keranjang (qty ±, subtotal), submit draft
  idempoten (`client_key` localStorage, dirotasi setelah sukses), pesan
  error spesifik (rate_limited / invalid_table_token / product_unavailable),
  halaman konfirmasi referensi ("Pesanan belum dibayar"), responsive
  grid 2/3 kolom + bottom bar + sheet; ikon cek SVG tanpa emoji.
- [x] **S03-03** Backend draft: migrasi `20261026000008_qr_drafts.sql`
  (tabel `qr_drafts`/`qr_draft_items` dengan snapshot nama+harga+modifier,
  status PENDING/CLAIMED/EXPIRED/CANCELLED/COMPLETED; RLS aktif tanpa
  policy = tertutup bahkan untuk operator via REST).
- [x] **S03-04** Submit publik anon `qr_submit_draft` (SECURITY DEFINER):
  validasi token, katalog aktif, qty 1–99, rate limit 5 draft/meja/10
  menit, idempotensi `client_key` unik per meja; harga = snapshot server
  (memakai helper `pos_line_total` Sprint 02).
- [x] **S03-05** API operator: `qr_list_drafts` (volatile, lazy-expire),
  `qr_claim_draft` atomik (sekali claim saja, audit event),
  `qr_cancel_draft`, `qr_complete_draft`; grants: anon hanya `qr_submit_draft`.
- [x] **S03-06** Panel "QR Masuk" di dalam layar POS:
  `qr_inbox_sheet.dart` (daftar draft + subtotal + item snapshot +
  ambil/batalkan) + badge berangka di baris pencarian katalog (tampil di
  layout lebar & HP) + polling `qrDraftsProvider` tiap 10 detik.
- [x] **S03-07** Ambil draft ke keranjang + konflik harga:
  `_claimDraft` me-refresh katalog (`ref.refresh(productsProvider.future)`)
  lalu membandingkan snapshot `unitPrice` vs harga terkini; dialog
  konflik (Pakai harga terkini / Batal); claim server mendahului
  pemasukan ke keranjang; produk hilang/tidak aktif dilewati + dilaporkan.
- [x] **S03-08** Bayar memakai checkout Sprint 02 tanpa diubah:
  setelah sukses, `_completeClaimedDrafts` memanggil `qr_complete_draft`
  (jejak audit sale_id); draft tidak pernah mengubah omzet.
- [x] **S03-09** Test: `tests/integration/test_qr_drafts.py` (REST
  Supabase asli) + widget test `test/features/qr_inbox_sheet_test.dart`
  (4 test) + `shell_test.dart` diperbarui (halaman Meja & QR nyata).

### Verifikasi
| Pengujian | Perintah/langkah | Hasil | Bukti |
|---|---|---|---|
| Analyze/lint | `flutter analyze` | **PASS** | 0 error/warning (9 info `unnecessary_underscores`, pola lama) |
| Unit/widget Flutter | `flutter test` | **PASS** | 33/33 (4 baru panel QR Masuk) |
| Migrasi | `supabase db push` | **PASS** | `0008_qr_drafts`, `0009_table_qr_api` "Finished"; 3 koreksi live tercatat di bawah |
| Uji REST draft | `python3 tests/integration/test_qr_drafts.py` | **PASS** | **37 PASS, 0 FAIL** |
| Build web POS | `flutter build web --release --dart-define=…QR_WEB_URL=…` | **PASS** | `✓ Built build/web` |
| Build web QR | `npm run build` (apps/qr_web) | **PASS** | `✓ built`, dist 299 kB |
| Buktian UI end-to-end (Chrome) | tablet 1280×800 + dua tab HP 360×740 via HTTPS aktual | **PASS** | 19 screenshot `docs/evidence/sprint03/` |

### Skenario uji wajib (hasil nyata)
- **2 "HP" submit bersamaan** → dua draft terpisah Q00029 (Meja HP-A, Rp 22.000) dan Q00030 (Meja HP-B, Rp 18.000) — screenshot 06/07.
- **Draft bukan omzet**: dashboard sebelum claim Rp 79.000; setelah checkout Q00029 → struk MJ-261026-0006 Rp 22.000 (satu sale, tepat +22.000); DB: Q00029 COMPLETED terhubung `sale_id=6` — screenshot 11/12/13.
- **Konflik harga**: Nasi Goreng diubah 20.000→21.000 setelah draft Q00031 terkirim (snapshot 20.000); klaim → dialog konflik "Rp 20.000 → Rp 21.000" → Pakai harga terkini → struk MJ-261026-0007 Rp 21.000 — screenshot 14/15/16. (Bug ditemukan & diperbaiki saat uji: deteksi konflik memakai cache katalog lama; kini refresh provider sebelum membandingkan.)
- **Retry idempoten**: key sama → `Q00032` dua kali, `idempotent_replay: true`.
- **Invalid token**: halaman Vue "QR tidak valid atau sudah diganti" — screenshot 19; REST: `invalid_table_token`.
- **Rate limit**: percobaan ke-6 per meja dalam 10 menit ditolak `rate_limited`.
- **Refresh/reconnect**: reload halaman pelanggan → menu reload normal; draft tak terduplikasi.
- **Rotasi token via UI**: Meja QR HP-B dirotasi → dialog token baru + QR (screenshot 17); URL lama langsung "QR tidak valid" (screenshot 18).
- **Akses publik tidak sah**: anon ditolak `qr_list_drafts`/`qr_claim_draft`/`qr_cancel_draft`/`qr_complete_draft`/`pos_checkout`; `qr_drafts` via REST operator = `[]` (RLS tertutup — semua akses lewat fungsi definer).
- **Draft tidak memengaruhi omzet** sampai dibayar (diuji REST: today/all-time revenue identik sebelum–sesudah submit).

### Temuan dan perbaikan saat pengujian
- Migrasi 0008 gagal push pertama: dua klausa `using` pada `raise exception` harus digabung (`using errcode=…, hint=…`) — diperbaiki sebelum terpasang.
- Live (migrasi sudah ter-push, dikoreksi via psycopg2 + dicatat): `subtotal`/`item_count` default 0 (insert sebelum dihitung), `qr_list_drafts` `stable`→`volatile` (ber-UPDATE), `claimed_by` bigint→uuid + FK `auth.users` (konsisten `created_by` sales).
- Bug klien: deteksi konflik harga memakai cache katalog → katalog di-refresh dulu di `_claimDraft`; build ulang & diverifikasi ulang end-to-end.
- Vite preview memblokir host tunnel (`allowedHosts`) — untuk evidence, `dist` disajikan `python3 -m http.server` (tanpa pemeriksaan host).

### Sisa pekerjaan / risiko
- URL QR evidence memakai tunnel cloudflared sementara (`QR_WEB_URL` di-build dengan URL itu); **hosting permanen = keputusan user** — saat tunnel mati, QR menampilkan "QR tidak valid" (jujur).
- Pengujian Android fisik ditunda (perangkat tidak tersedia).
- S01-08 tetap BLOCKED (menunggu remote GitHub).
- Fixture uji di DB: Es Teh id 13 kini Rp 10.000, Nasi Goreng id 4 kini Rp 21.000 (riwayat harga tercatat); meja uji `UJI-QR-*` dapat diarsipkan/dihapus lewat SQL bila perlu.

## Sprint 02 — Katalog & Kasir POS (End-to-End)
Tanggal: 26 Oktober 2026
Target/tiket: S02-01 … S02-10
Status: **DONE** — semua tiket lulus dengan bukti nyata (Supabase asli + web build di Chrome); pengujian perangkat Android ditunda (perangkat tidak tersedia saat sesi ini)

### Yang dibangun
- [x] **S02-01** CRUD katalog: `features/catalog/catalog_page.dart` +
  `catalog_repository.dart` (kategori, produk, foto via `image_picker` →
  bucket Storage publik `product-photos`, arsip tanpa hapus histori).
  Migrasi `20261026000007_product_photos.sql` (dilewati aman di CI polos).
- [x] **S02-02** Varian/topping: modifier global + `product_modifiers`
  min/max; sheet pemilihan modifier di POS menolak di luar batas (validasi
  server `pos_line_total` juga menolak `modifier_max_exceeded`).
- [x] **S02-03** Harga adjustable + riwayat: trigger
  `product_price_history` (migrasi S01) + tampilan riwayat per produk.
- [x] **S02-04** UI `Kasir POS` (`pos_page.dart`): layout adaptif —
  tablet ≥840dp katalog+keranjang bersamaan; HP katalog penuh + bar keranjang
  yang membuka sheet; pencarian, filter kategori, qty ±, catatan, hapus.
- [x] **S02-05** Quote server: fungsi Postgres `pos_quote` /
  `pos_line_total` (SECURITY DEFINER, hanya `authenticated`); klien
  mengirim keranjang mentah, server hitung ulang subtotal/diskon/pajak/
  layanan/total, pembulatan `ROUND` half-up.
- [x] **S02-06** Sheet pembayaran: tunai/transfer/QRIS manual, nominal
  diterima, kembalian (server menolak `insufficient_payment`).
- [x] **S02-07** DB transaksi + checkout atomik: migrasi
  `20261026000005_sales.sql` (`sales`, `sale_items` snapshot nama+harga+
  modifier, `payments`, `refunds`, `audit_events`, RLS operator) +
  `20261026000006_pos_api.sql` (`pos_checkout` idempoten via
  `sales.idempotency_key` unik, nomor struk dari sequence).
- [x] **S02-08** Riwayat + struk: `sales_history/history_page.dart`
  (daftar, pencarian no. struk, detail struk snapshot, dialog refund
  bervalidasi — nominal ≤ sisa, alasan ≥3 karakter).
- [x] **S02-09** Dashboard omzet: `dashboard_page.dart` dari RPC
  `pos_dashboard_summary` (hanya sale final, net terhadap refund).
- [x] **S02-10** Test: `tests/integration/test_pos_api.py` (REST Supabase
  asli) + unit test cart `test/features/cart_state_test.dart`.

### Verifikasi
| Pengujian | Perintah/langkah | Hasil | Bukti |
|---|---|---|---|
| Analyze/lint | `flutter analyze` | **PASS** | 0 error/warning (7 info `unnecessary_underscores`, konsisten pola lama) |
| Unit/widget Flutter | `flutter test` | **PASS** | 29/29 (20 lama + 9 cart: merge baris, batas qty, urutan modifier, lineTotal) |
| Migrasi transaksi | `supabase db push` | **PASS** | `0005_sales`, `0006_pos_api`, `0007_product_photos` "Finished" |
| Uji REST uang/rounding | `python3 tests/integration/test_pos_api.py` | **PASS** | **73 PASS, 0 FAIL** — 20 skenario quote, 21 skenario pajak/layanan (rounding half-up), checkout idempoten (double tap + 10 retry → 1 sale), snapshot harga saat master diedit, refund parsial/penuh/over-limit, anon ditolak semua API uang |
| Build web | `flutter build web --release --dart-define=…` | **PASS** | `✓ Built build/web` |
| Buktian UI end-to-end (Chrome, tablet 1280×800) | login → katalog → POS → bayar → riwayat → refund → dashboard | **PASS** | 18 screenshot `docs/evidence/sprint02/` (lihat di bawah) |

### Alur bukti end-to-end (Chrome, bukan mock)
1. Login operator (`01-dashboard-omzet.png`) — dashboard menampilkan data server asli.
2. Tambah kategori "Minuman" (`02-kategori-minuman.png`); kategori salah ketik diarsipkan (`02b-setelah-arsip-kategori-salah.png`).
3. Buat menu "Es Teh Manis Jumbo" Rp 8.000 kategori Minuman (`03-form-menu-baru.png`, `04-menu-baru-tersimpan.png`) — terverifikasi REST: produk id 13.
4. Ubah harga 8.000→9.000 + tambah topping "Cincau +Rp 2.000" (`05-ubah-harga-topping.png`); riwayat harga mencatat perubahan (`06-riwayat-harga.png`).
5. Kasir POS: katalog+keranjang bersamaan (`07-pos-tablet-katalog-keranjang.png`); 2× Es Teh+Cincau + 1 Nasi Goreng.
6. Quote server Total Rp 40.000 (`08-quote-server-total-40000.png`); bayar tunai Rp 50.000 → kembalian Rp 10.000 (`09-kembalian-10000.png`).
7. Struk MJ-261026-0003 dengan snapshot modifier (`10-struk-transaksi.png`).
8. Double-tap bayar: klik konfirmasi 2× → **satu** struk; via REST key sama → sale sama + `idempotent_replay: true` (MJ-261026-0004).
9. Riwayat penjualan (`11-riwayat-penjualan.png`); struk snapshot harga lama tetap (`12-struk-snapshot.png`).
10. Refund Rp 50.000 > sisa → ditolak validasi (`13-refund-ditolak-lebih-total.png`).
11. Refund sah Rp 11.000 parsial → struk net Rp 29.000 + riwayat refund (`14-refund-parsial-struk-net.png`); DB: `PARTIALLY_REFUNDED`, uang historis tetap utuh.
12. Dashboard: omzet hari ini Rp 47.000 (40.000−11.000 + 18.000), 2 transaksi final, refund Rp 91.000 (`15-dashboard-setelah-refund.png`) — cocok hitungan SQL.
13. Perbaikan: daftar riwayat segar setelah refund (`16-riwayat-status-refund.png`).

### Acceptance Criteria
- [x] Item baru tampil di POS; arsip tidak menghapus histori.
- [x] Total per item tepat untuk kombinasi modifier (server menolak di luar min/max).
- [x] Transaksi terdahulu tak berubah setelah edit harga (diuji REST + struk UI).
- [x] Semua aksi kasir dalam satu layar POS; tanpa halaman Pesanan.
- [x] Test 50+ skenario uang integer & rounding (73 pemeriksaan total).
- [x] Kembalian tidak negatif; server menolak bayar kurang.
- [x] Double-click key sama = satu sale (uji klik 2× + 10 retry REST).
- [x] Struk cocok pembayaran; pencarian no. struk berfungsi.
- [x] Angka dashboard cocok query SQL.
- [x] Refund dicatat beralasan, tidak menghapus uang historis.

### Temuan dan perbaikan
- Masalah: daftar Riwayat menampilkan status lama setelah refund (provider
  tidak di-invalidate).
  Perbaikan: `ref.invalidate(salesListProvider)` setelah refund sukses;
  diverifikasi ulang di web (`16-riwayat-status-refund.png`).
- Catatan pengujian otomatis Chrome: keystroke pertama pada sebagian input
  Flutter-web tidak terekam (kehilangan huruf awal) — artefak automasi
  accessibility, bukan bug aplikasi; ditangani saat uji dengan mengisi ulang
  field. Di perangkat sentuh nyata tidak terjadi.
- Uji double-tap di UI: tombol Konfirmasi dinonaktifkan saat `_submitting`
  berjalan; retry memakai idempotency key yang sama sehingga server
  mengembalikan sale yang sama (`idempotent_replay: true`).

### Sisa pekerjaan
- Pengujian di perangkat Android fisik (APK sudah dibangun lulus) ditunda
  hingga perangkat tersedia — jalankan `adb install` + alur bukti yang sama.
- S01-08 tetap BLOCKED (menunggu remote GitHub).

## Sprint 01 — Laporan Implementasi
Tanggal: 26 Oktober 2026
Target/tiket: S01-01 … S01-08
Status: **DONE kecuali S01-08** (CI GitHub menunggu remote Git; seluruh tiket lain lulus dengan bukti perangkat nyata)

### Yang dibangun
- [x] **S01-01** Monorepo: `apps/pos_flutter` (Flutter), `apps/qr_web` (Vue/Vite),
  `supabase/migrations`, `.env.example` root + per app, `README.md` (commit `a039446`).
- [x] **S01-02** Design tokens `#930031` + M3 theme di `lib/app/theme.dart`;
  widget `ModulePlaceholder`, kartu, tombol, input mengikuti token.
- [x] **S01-03** Shell adaptif `lib/app/shell.dart` + `lib/app/destinations.dart`:
  sidebar 3 grup (13 halaman) di tablet ≥840dp; bottom nav 5 item
  (Beranda/Kasir/Stok/Laporan/Lainnya) di HP. Setiap modul memakai empty state
  jujur "Menyusul: Sprint NN" — tidak ada angka palsu, tanpa halaman
  Dapur/Pesanan/Pegawai.
- [x] **S01-04** Auth satu operator: `features/auth/auth_repository.dart` +
  `login_page.dart` (validasi form, loading, pesan error bahasa Indonesia).
  Akun Supabase Auth `operator@mejeng.id` dibuat dan login diuji via REST.
- [x] **S01-05** Migrasi `20261026000001…04`: `business_settings` (1 baris),
  `product_categories`, `products` (integer Rupiah), `product_price_history`
  (trigger otomatis), `modifiers`, `product_modifiers` (min/max), `dining_tables`
  (hash token). Seed `supabase/seed/seed_dev.sql` berlabel `[DEMO]`.
- [x] **S01-06** RLS ketat: fungsi `is_operator()` (SECURITY DEFINER),
  policy `operator_all` di 7 tabel privat, API publik `get_public_menu(token)`.
- [x] **S01-07** Riverpod provider, `formatters.dart` (Rupiah id-ID, WIB manual
  UTC+7), `error_mapper.dart`, `.env.example` adapter (`--dart-define`).
- [x] **S01-08** `.github/workflows/ci.yml`: job `flutter` (analyze+test),
  `qr-web` (npm ci+build), `migrations` (Postgres 15 polos + stub auth).

### Verifikasi
| Pengujian | Perintah/langkah | Hasil | Bukti |
|---|---|---|---|
| Analyze/lint | `flutter analyze` | **PASS** | "No issues found" |
| Unit/widget Flutter | `flutter test` | **PASS** | 20/20 lulus (formatters, error mapper, theme, shell tablet/HP, login, regresi overflow landscape) |
| Build web QR | `npm run build` (apps/qr_web) | **PASS** | bundle 293 kB, tanpa error |
| Dev server QR | `npm run dev` → `curl localhost:5199` | **PASS** | HTTP 200 |
| Migrasi ke Supabase asli | `supabase db push --db-url …` | **PASS** | 4 migrasi "Finished" |
| Menu publik token valid | `POST /rest/v1/rpc/get_public_menu` token `dev-table-01-token` | **PASS** | kategori + 10 produk `[DEMO]` kembali |
| Token salah | RPC dengan `tokoh-salah` | **PASS** | `invalid_table_token` |
| Anon baca tabel privat | `GET /rest/v1/products` anon | **PASS** | `[]` (RLS menutup) |
| Anon tulis produk | `POST /rest/v1/products` anon | **PASS** | HTTP 401 |
| Operator login REST | `password grant` | **PASS** | access token terbit |
| Operator baca settings | `GET business_settings` + sesi operator | **PASS** | 1 baris usaha |
| Trigger harga | PATCH harga produk uji 10000→12000 | **PASS** | `product_price_history` tercatat (dibersihkan sesudah uji) |
| Build APK debug | `flutter build apk --debug --dart-define=…` | **PASS** | `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (147,6 MB) |
| Install + `flutter run` di perangkat fisik | OPPO CPH2473 (Android 14, USB, id `272903cc`) | **PASS** | aplikasi terpasang, `Supabase init completed`, UI tergambar |
| Login operator di perangkat | ketik email+sandi → Masuk | **PASS** | header menampilkan `operator@mejeng.id` (`device-01/02`) |
| Navigasi HP portrait | tap Beranda/Lainnya | **PASS** | bottom nav 5 item + sheet Lainnya (`device-03`) |
| Landscape HP | rotasi dipaksa `user_rotation 1` | **PASS** | shell menyesuaikan tanpa crash (`device-04`) |

### Acceptance Criteria
- [x] `npm run dev`/`build` jalan dengan `.env.example` (QR web).
- [x] Brand `#930031`, Material Icons, tanpa emoji, tanpa halaman AI.
- [x] 1 identitas operator; tanpa role switch.
- [x] Publik vs operator terpisah (uji REST nyata di atas).
- [x] Shell tablet + HP teruji widget test; tanpa Dapur/Pesanan/Pegawai.
- [x] `flutter run` di perangkat Android fisik (OPPO CPH2473): **lulus** —
  install, login operator nyata, navigasi HP portrait & landscape; screenshot
  di `docs/evidence/sprint01/`.
- [ ] GitHub Actions hijau: **belum** — repository belum dipush ke GitHub.

### Temuan dan perbaikan
- Masalah: fungsi `digest()` gagal di Supabase (`digest(text, unknown) does not exist`).
  Penyebab: pgcrypto terpasang di skema `extensions`, sedangkan fungsi
  `SECURITY DEFINER` memakai `search_path = public`.
  Perbaikan: migrasi `20261026000004_fix_pgcrypto_search_path.sql` +
  kualifikasi `extensions.digest` (idempoten untuk CI Postgres polos).
  Regression check: menu publik token valid kembali berfungsi.
- Masalah: `formatWib` melempar `LocaleDataException` di unit test.
  Penyebab: `DateFormat('id-ID')` butuh `initializeDateFormatting`.
  Perbaikan: nama bulan Indonesia statis (deterministik, tanpa dependensi).
- Masalah (**ditemukan di perangkat fisik, lolos semua tes sebelumnya**):
  `ModulePlaceholder` `BOTTOM OVERFLOWED BY 112 PIXELS` di landscape HP
  (viewport tinggi ≈240dp, kartu terpusat tanpa scroll).
  Penyebab: `Center + Card` tanpa jalur scroll pada viewport pendek.
  Perbaikan: `LayoutBuilder + SingleChildScrollView + minHeight`
  (`lib/core/widgets/module_placeholder.dart`) + test regresi
  `test/core/module_placeholder_test.dart` (viewport 640×240, drag sampai
  chip terlihat). Verifikasi ulang: analyze 0 issue, 20/20 test lulus,
  APK baru di-install ke perangkat dan landscape diuji ulang tanpa strip
  overflow (`device-05-landscape-tanpa-overflow.png`).

### Sisa pekerjaan
- BLOCKED: S01-08 — push repository ke GitHub agar CI berjalan nyata (butuh
  remote/akun dari pemilik proyek).
- Gate S01: dua butir pertama lulus; butir "layout tablet/HP layak navigasi"
  lulus di HP nyata (portrait + landscape). Sidebar tablet 840dp tidak dapat
  dibuktikan di ponsel ini (lebar landscape hanya 640dp) — terverifikasi lewat
  `flutter build web` + widget test.
- Tiket pertama berikutnya: **S02-01** (CRUD kategori/menu/harga di Flutter).

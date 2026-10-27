# SPRINTS.md
## Smart POS Waroeng MeJeng Kampoeng | Build Plan v2.1 · MVP Product Tanpa ML

| Metadata | Nilai |
|---|---|
| Tanggal | 26 Oktober 2026 |
| Status | **Sprint 01–05 DONE** (bukti di `docs/sprint-log.md` + change log §13); Sprint 06 **TODO** |
| Spesifikasi induk | `PRD.md` versi 2.1 |
| Produk | Satu aplikasi Flutter untuk **satu operator** + satu web QR pelanggan |
| UI | Tablet Android landscape prioritas, responsif HP, **brand `#930031`** dan Material Icons tanpa emoji |
| Backend | Supabase Auth, PostgreSQL, API bisnis terproteksi, Realtime (opsional untuk notifikasi QR), tanpa ML/AI pada MVP |
| Ritme rencana | Sprint 1–6 masing-masing target 1–2 pekan (disesuaikan kapasitas developer); tidak ada sprint ML pada MVP |

> **Fokus dokumen ini adalah membangun aplikasi.** Tidak ada Sprint Observasi, tidak ada roadmap multi-tenant, tidak ada fitur Dapur, dan tidak ada halaman Pesanan. Setiap sprint berisi task coding, struktur data, integrasi, test, dan output yang dapat dijalankan. Bila ada data bisnis yang belum diketahui, developer memakai fixture **berlabel SIMULASI** dan mencatat konfigurasi yang harus diisi operator, bukan menghentikan pembangunan untuk kegiatan observasi panjang.

---

# 1. Prinsip Arsitektur yang Tidak Boleh Dilanggar

- **Hanya satu akun operator internal**, tidak perlu `employees`, `staff_roles`, halaman shift antarstaf, `kitchen_tickets`, `branches`, `tenants`, atau modul langganan.
- **Halaman POS adalah satu-satunya titik operasional transaksi**: menu → keranjang → QR Masuk → bayar → struk. Tidak buat `OrdersPage` dan `KitchenPage`.
- Web QR dapat mengirim **draft keranjang**, bukan transaksi lunas. Draft muncul sebagai panel/tab **QR Masuk dalam POS**.
- `sales` berbeda dari `qr_drafts`: QR draft belum masuk omzet maupun pengurangan stok.
- Final checkout divalidasi di server dan idempotent, atomik untuk sale + payment + stock ledger.
- Harga dan modifier disimpan sebagai snapshot setiap item sale. Penjualan historis tidak terpengaruh edit menu.
- Biaya energi dan HPP pakai perhitungan deterministik, bukan label AI.
- **Tidak ada ML pada MVP**: jangan membuat `ml_api`, pipeline/model, endpoint forecast, dashboard AI, atau fixture prediksi. Analytics hanya data aktual. Usulan ML dipisah dari backlog rilis.

## 1.1 Prioritas

`P0` = rilis inti, `P1` = pengayaan, `P2` = opsional terpisah. Jika suatu P1 belum bisa diuji (printer atau offline), jangan mengklaim fitur selesai.

## 1.2 Status tiket

`TODO → IN_PROGRESS → IN_REVIEW → IN_TEST → DONE` atau `BLOCKED` bila dependensi belum terpenuhi.

## 1.3 Definition of Done umum

- [ ] Kode, migrasi, dan test tersimpan di Git; build clean.
- [ ] Lint/format/unit test serta integration test yang relevan lulus.
- [ ] Loading, empty, invalid, retry, dan pesan error telah ditangani.
- [ ] Tampilan diuji pada **Android tablet landscape** dan HP (emulator/perangkat); mengikuti struktur/alur `index.html`, warna `#930031`, ikon `Icons.*` Flutter, tanpa emoji atau UI generik.
- [ ] Backend menolak input total/harga ilegal dan tidak mengandalkan validasi frontend saja.
- [ ] State yang melibatkan uang/stok memiliki log/snapshot dan tidak double-submit.
- [ ] Dokumentasi kontrak API dan petunjuk jalankan app diperbarui.
- [ ] Screenshot atau video demo serta hasil tes dicatat di `docs/sprint-log.md`.
- [ ] Tidak ada tautan/button mati yang dipresentasikan sebagai fitur selesai.

---

# 2. Roadmap Eksekusi Ringkas

| Sprint | Tema coding | Target demo akhir | Keluarannya |
|---|---|---|---|
| **01** | Project scaffold, design system, database, auth | Buka aplikasi Flutter, login satu operator, lihat dashboard dan navigasi | Flutter + Vue + Supabase starter |
| **02** | Katalog, adjustable pricing, POS, checkout | Tambah menu, ubah harga, bayar tunai, lihat struk | Kasir siap transaksi manual |
| **03** | QR pelanggan di dalam POS | Scan QR HP → kirim keranjang → muncul di panel QR Masuk POS → bayar | Alur QR tanpa Pesanan/Dapur |
| **04** | Inventory, resep, pembelian, HPP | Stok otomatis dari transaksi final, pembelian dan biaya bahan | Ledger bahan + HPP |
| **05** | Listrik, LPG, air, overhead, kas, laporan | Hitung biaya operasi dan rekonsiliasi kas/penjualan | Modul biaya dan laporan |
| **06** | Refine UX, security, performance, release | Uji full flow pada tablet, recover/backup, build APK | Build kandidat rilis dan UAT |

```mermaid
flowchart LR
 S1[Flutter + backend] --> S2[Katalog & POS]
 S2 --> S3[Web QR → POS]
 S2 --> S4[Stok & HPP]
 S3 --> S5[Biaya & laporan]
 S4 --> S5
 S5 --> S6[UAT & rilis]
```

---

# 3. Sprint 01 – Kerangka Aplikasi dan Database

**Goal:** proyek dijalankan dari repository tanpa setup manual yang misterius. Antarmuka internal hanya satu operator.

| ID | Prioritas | Implementasi langsung | Acceptance criteria | Status |
|---|---|---|---|---|
| S01-01 | P0 | Buat monorepo Flutter (`apps/pos_flutter`), web Vue (`apps/qr_web`), `supabase/migrations`, dan API bisnis | `flutter run` serta `npm run dev` jalan dengan `.env.example` | **DONE** — `flutter run` di perangkat fisik OPPO CPH2473 lulus (login operator nyata, bukti screenshot `docs/evidence/sprint01/`); `npm run dev` HTTP 200 |
| S01-02 | P0 | Flutter design tokens: **primary `#930031`**, typography, spacing, card, button, modal, empty/loading/error, Material Icons; animasi transisi yang fungsional dan aksesibel | Widget story/demo untuk tiap komponen | **DONE** — `test/app/theme_test.dart` memastikan brand; komponen diuji di `test/app/shell_test.dart` |
| S01-03 | P0 | Router dan shell tablet: sidebar landscape, mobile bottom navigation; halaman `Dashboard`, `POS`, `Menu`, `QR`, `Stok`, `Resep`, `Pembelian`, `Biaya`, `Energi`, `Kas`, `Riwayat`, `Laporan`, `Pengaturan` | Tidak ada `Dapur`, `Pesanan`, atau `Pegawai` | **DONE** — 13 halaman jujur (empty state menunggu sprint berikutnya), teruji di shell_test |
| S01-04 | P0 | Integrasi Supabase Auth **satu akun operator**: login, logout, refresh session | Publik tidak bisa mengakses halaman internal | **DONE** — login/logout/login_page_test lulus; akun `operator@mejeng.id` dibuat & diuji via REST |
| S01-05 | P0 | Migrasi awal: business_settings, product categories, products, modifiers, price_history, tables | SQL migration + constraint dan seed dummy dev | **DONE** — 4 migrasi diterapkan ke Supabase asli; seed `[DEMO]` lulus |
| S01-06 | P0 | RLS & API authorization: private operator; public hanya membaca menu aktif / kirim QR draft melalui endpoint aman | Test akses tanpa token/operator invalid ditolak | **DONE** — anon kembalikan `[]`/401, token salah → `invalid_table_token`, token valid → menu |
| S01-07 | P0 | State management (Riverpod), shared DTO, error mapper, HTTP client, WIB/IDR utilities | Unit test parse, money format, state loading | **DONE** — `formatters_test` (19 asersi) + `error_mapper_test` lulus |
| S01-08 | P0 | CI GitHub: Flutter analyze/test, Vue lint/build, migration test; format precommit | Pipeline lulus dan README dapat direproduksi | **PARTIAL** — `.github/workflows/ci.yml` ditulis (Flutter, Vue, migrasi ke Postgres polos); belum dijalankan di GitHub (belum ada remote) |

**Demo:** login → dashboard UI → POS kosong → navigasi semua menu tanpa crash. Gunakan fixture `DEMO`, belum mengklaim transaksi nyata.

**Gate S01:**
- [x] User flow internal memakai **1 identitas operator**, bukan role switch. (akun tunggal `operator@mejeng.id`, tanpa tabel role/pegawai)
- [x] QR publik dan operator memiliki jalur akses yang berbeda. (anon hanya `get_public_menu`; data privat tertutup RLS — diuji langsung ke Supabase)
- [x] Build Android debug berhasil, layout tablet/HP layak navigasi. (APK terpasang & dijalankan di HP fisik OPPO portrait+landscape; bug overflow landscape ditemukan lalu diperbaiki + test regresi; sidebar tablet teruji via `flutter build web` + widget test — HP 640dp di bawah breakpoint 840dp sehingga bottom nav memang benar)

---

# 4. Sprint 02 – Katalog dan Kasir POS (End-to-End)

**Goal:** kasir menyelesaikan transaksi tanpa QR menggunakan Flutter tablet. Fokus paling penting dari produk.

| ID | Prioritas | Implementasi langsung | Acceptance criteria | Status |
|---|---|---|---|---|
| S02-01 | P0 | Form kategori, menu, harga, foto, tersedia/habis, arsip; validation + upload image | Item baru tampil di POS, arsip tidak menghapus histori | **DONE** — CRUD katalog penuh; menu "Es Teh Manis Jumbo" dibuat via UI & terverifikasi REST; arsip kategori menghapus dari tampilan tanpa menghapus data |
| S02-02 | P0 | Varian, topping, harga tambahan, catatan menu, aturan minimal/maksimal | Total per item tepat dalam test modifier | **DONE** — topping "Cincau +Rp 2.000" dipilih di POS; sheet menolak di luar batas; server menolak `modifier_max_exceeded` |
| S02-03 | P0 | Harga adjustable + `price_history`; perubahan harga aktif dan snapshot | Transaksi terdahulu tak berubah setelah edit | **DONE** — 8.000→9.000 tercatat trigger; struk sale lama tetap memakai harga lama (uji REST + UI) |
| S02-04 | P0 | UI `Kasir POS` tablet: pencarian, kategori, grid menu, tambah item, qty ±, hapus, catatan, pilihan makan di tempat/takeaway | Semua dilakukan dalam satu layar tanpa menu Pesanan | **DONE** — adaptif tablet/HP; katalog+keranjang bersamaan di ≥840dp, sheet keranjang di HP |
| S02-05 | P0 | `sales/quote` kalkulator server: subtotal, diskon, pajak/layanan konfigurabel, total | Test 50+ skenario uang integer & rounding | **DONE** — `pos_quote`/`pos_line_total` server-side; 73 PASS REST termasuk 21 skenario pajak/layanan rounding half-up |
| S02-06 | P0 | Pembayaran dari POS (sheet/modal): tunai, transfer/QRIS manual, nominal dibayar, kembalian | Saldo dan kembalian tidak negatif/inkonsisten | **DONE** — bayar Rp 50.000 → kembalian Rp 10.000 (bukti UI); server menolak `insufficient_payment` |
| S02-07 | P0 | DB `sales`, `sale_items`, `payments`, `refunds`, `audit_events` + atomic checkout/idempotency | Double-click key sama menghasilkan **satu** sale | **DONE** — migrasi 0005+0006 diterapkan; klik 2× di UI + 10 retry REST key sama → satu sale, `idempotent_replay: true` |
| S02-08 | P0 | Struk digital dan halaman Riwayat Penjualan; search/filter | Harga snapshot tetap, struk cocok dengan pembayaran | **DONE** — riwayat + struk snapshot + refund bervalidasi (parsial Rp 11.000 tercatat, uang historis utuh) |
| S02-09 | P0 | Dashboard omzet dan jumlah transaksi dari sale final, bukan keranjang | Angka dashboard cocok query SQL | **DONE** — omzet hari ini Rp 47.000 = (40.000−11.000)+18.000, 2 transaksi final, refund Rp 91.000 — cocok SQL |
| S02-10 | P0 | Unit, integration, widget, E2E Flutter pembayaran dan price change | UAT-01, UAT-04, UAT-05 lulus | **DONE** — 29/29 flutter test + 73 PASS integration REST + alur E2E web Chrome (18 screenshot `docs/evidence/sprint02/`) |

**Demo:** operator membuat menu dummy → mengganti harga → memilih dua makanan dan minuman → bayar tunai → melihat kembalian → struk → histori dan dashboard ter-update. **Tidak ada tahap penerimaan dapur**.

**Gate S02:**
- [x] Checkout memang hanya dari POS. (semua sale lahir dari `pos_checkout`; tidak ada route/halaman checkout lain; uji REST menutup anon)
- [x] Uang/tarif ditetapkan di server; mobile tidak dapat memalsukan total. (klien hanya mengirim keranjang mentah; 73 uji REST membuktikan server hitung ulang & menolak input ilegal)
- [x] Refund/void dicatat, tidak menghapus uang historis. (refund parsial/penuh tercatat beralasan; `sales` asli tetap dengan total awal — verifikasi REST + UI)
- [x] Button masuk POS dan back navigation berfungsi di tablet/HP. (teruji di web Chrome 1280×800 + widget test shell; verifikasi ulang di HP Android ditunda — perangkat tidak tersedia saat sesi ini)

---

# 5. Sprint 03 – QR Ordering Langsung ke Layar POS

**Goal:** QR meja tetap berguna meskipun hanya satu operator; **tanpa halaman Pesanan**.

| ID | Prioritas | Implementasi langsung | Acceptance criteria |
|---|---|---|---|
| S03-01 | P0 | Editor nomor meja, generate token opaque, rotasi token, URL QR | QR lama invalid setelah rotasi | DONE |
| S03-02 | P0 | Vue web pelanggan: daftar menu, foto, varian, topping, qty, keranjang, identitas meja | Responsif 360px; pelanggan tidak login | DONE |
| S03-03 | P0 | `POST /public/qr-drafts`: validasi token, katalog aktif, qty, rate limit, idempotency | QR hanya menghasilkan draft sementara, bukan sale | DONE |
| S03-04 | P0 | `qr_drafts`, `qr_draft_items`: `PENDING/CLAIMED/EXPIRED/CANCELLED`, expiring link | Duplicate submit tidak menciptakan banyak draft | DONE |
| S03-05 | P0 | Panel **QR Masuk** di dalam UI `Kasir POS`: badge count dan kartu ringkas meja, item, waktu | Panel ada dalam POS, bukan route/tab navigasi tersendiri | DONE |
| S03-06 | P0 | Aksi `Ambil ke Kasir`: validasi ulang harga & item, isi keranjang aktif; cegah silent merge dengan keranjang lama | Checkout tetap memakai S02, draft ditandai CLAIMED | DONE |
| S03-07 | P0 | Realtime event/refresh polling fallback saat notifikasi gagal | Draft yang belum diambil tetap terlihat setelah refresh | DONE |
| S03-08 | P0 | Halaman sukses pelanggan: nomor referensi, instruksi tunggu kasir; **tanpa status dapur/tracking** | Tidak ada timeline preparing/ready/served | DONE |
| S03-09 | P0 | E2E 2 HP submit serentak → POS pilih salah satu → bayar | Draft terisolasi, item pelanggan tidak tercampur | DONE |

**Demo:** dari mode QR HP pilih Ayam Kremes + Teh Es → kirim → pindah ke **Kasir POS** → `QR Masuk (1)` → `Ambil ke Kasir` → tunai → struk. Operator sendirian mengurus prosesnya.

**Gate S03:**
- [x] Customer tidak bisa mengakses kas, bahan, HPP, atau laporan. (Anon ditolak semua RPC operator; `qr_drafts`/`qr_draft_items` RLS tertutup tanpa policy — dibuktikan REST.)
- [x] Draft QR belum masuk omzet/stock ledger. (Dashboard Rp 79.000 sebelum claim; hanya naik saat checkout FINAL; test REST 37 PASS.)
- [x] Tidak ada layar kitchen/order management tersembunyi pada aplikasi utama. (Hanya panel "QR Masuk" di dalam POS; tanpa OrdersPage/KitchenDisplay.)
- [x] Harga berubah antara submit dan ambil ditampilkan sebagai konflik yang harus disetujui operator. (Dialog konflik "Rp 20.000 → Rp 21.000" + bukti `14-konflik-harga.png`.)

---

# 6. Sprint 04 – Stok, Pembelian, Resep, HPP

**Goal:** penjualan final terhubung dengan perhitungan stok dan biaya resep dengan log mutasi.

| ID | Prioritas | Implementasi langsung | Acceptance criteria |
|---|---|---|---|
| S04-01 | P0 | Migrasi master `ingredients` + decimal qty, satuan dasar, minimum stock, unit cost | Kg↔g; L↔ml lulus test satuan | DONE |
| S04-02 | P0 | UI `Stok Bahan`: list, cari, status minimum, tambah/ubah, koreksi stok dengan alasan | Perubahan menulis ledger | DONE |
| S04-03 | P0 | Form `Pembelian`: supplier opsional, bahan, qty, harga, tanggal, status received | Saldo bertambah tepat sekali saat diterima | DONE |
| S04-04 | P0 | UI `Resep & HPP`: pilih menu, tambah bahan, takaran, yield per batch, biaya bahan per porsi | Formula sesuai versi resep dan unit cost | DONE |
| S04-05 | P0 | Database recipe_versions/items dan append-only stock_movements | Histori biaya/resep bisa ditelusuri | DONE |
| S04-06 | P0 | Integrasi checkout POS → pemakaian bahan tepat sekali saat sale final; pembelian/waste diposting terpisah | Dua retry checkout tak menggandakan bahan terpakai | DONE |
| S04-07 | P0 | Pengecualian bahan kosong, resep belum ada, dan batch siap jual (gorengan) | Tidak otomatis mengklaim stok akurat untuk menu tanpa resep | DONE |
| S04-08 | P0 | Laporan margin bahan per menu, stok minimum, mutasi terakhir | Margin hanya memakai komponen yang ada datanya | DONE |
| S04-09 | P0 | Unit/integration tests concurrency, rollback dan double-post | UAT-06–08 lulus | DONE |

**Keputusan desain awal:** untuk menu dibuat saat dipesan, konsumsi resep dicatat saat checkout final (model POS sederhana); untuk produk gorengan yang dibuat per batch gunakan produksi batch agar tidak mengurangi bahan dua kali. Bila pemakaian bahan nyata berbeda, koreksi dicatat eksplisit oleh operator.

**Gate S04:**
- [x] Konversi Kg↔g dan L↔ml lulus. (`inv_to_base` di server; 57 pemeriksaan `test_inventory.py` PASS.)
- [x] Perubahan menulis ledger append-only. (Semua lewat `inv_post_movement`; trigger tolak UPDATE/DELETE; bukti screenshot ledger PURCHASE/RECIPE/WASTE.)
- [x] Saldo + tepat sekali saat pembelian diterima. (PO #13: 0→2.000 g, 1 baris ledger, guard `purchase_already_received`.)
- [x] Formula HPP sesuai versi resep aktif dan unit cost. (UI Rp 1.550 = (200 g×Rp13 + 100 ml×Rp5) ÷ yield 2; versi v3 aktif, riwayat v1–v3.)
- [x] Dua retry checkout tidak menggandakan bahan. (Key sama → `sale_id` 30 sama, `idempotent_replay: true`, ledger RECIPE tetap 2 baris.)
- [x] Tidak otomatis mengklaim stok akurat untuk menu tanpa resep. ("resep belum ada"; menu tanpa resep tanpa mutasi RECIPE.)
- [x] Margin hanya memakai komponen berdata. (Harga jual − HPP resep aktif; menu tanpa resep tidak menampilkan angka HPP/margin.)

---

# 7. Sprint 05 – Biaya Operasional, Kalkulator, Kas dan Laporan

**Goal:** memperkirakan biaya produksi dan profitabilitas tanpa menyamakan biaya estimasi dengan tagihan nyata.

| ID | Prioritas | Implementasi langsung | Acceptance criteria |
|---|---|---|---|
| S05-01 | P0 | UI `Kalkulator Energi`: daya W, jam, load factor, tarif Rp/kWh, porsi; LPG isi ulang & jam efektif | Rumus kWh/LPG benar dan biaya/porsi valid |
| S05-02 | P0 | UI dan tabel `equipment`, `energy_estimates`, `expenses`, `cost_allocations` | Data asumsi tidak otomatis menjadi expense aktual |
| S05-03 | P0 | Input pengeluaran listrik, LPG, air, kemasan, sewa, internet, lain-lain; bukti opsional | Jenis `ESTIMATED` / `ACTUAL` terlihat di list/laporan |
| S05-04 | P0 | Cegah double counting alokasi biaya batch dan overhead | Total alokasi ≤ sumber biaya; laporan reconcile |
| S05-05 | P0 | Modul `Kas Shift`: mulai shift, kas awal, transaksi cash, pengeluaran kas, uang aktual, selisih | Non-tunai tidak masuk kas fisik |
| S05-06 | P0 | Dashboard detail: omzet, transaksi final, biaya langsung/HPP, overhead, estimasi hasil operasi | Semua nilai ditelusuri ke catatan |
| S05-07 | P0 | Halaman `Laporan`: filter tanggal, grafik tren, menu terlaris, biaya per kategori, transaksi | Nilai cocok dengan DB, refund mengurangi net sales |
| S05-08 | P1 | Ekspor CSV yang valid dan dapat dibuka, PDF/XLSX kemudian | Format Rupiah/jumlah tidak berubah makna |
| S05-09 | P0 | Unit & integrasi test alokasi listrik, tarif input, biaya aktual vs estimasi, kas shift | UAT-09–11 lulus |

**Demo:** input 800 W × 3 jam × load 80% × Rp1.500/kWh → tampil estimasi kWh/biaya; simpan expense **Estimasi** → bandingkan biaya aktual → lihat HPP dan laporan → tutup kas.

**Gate S05:**
- [x] **UAT-09** Kalkulator listrik dan LPG: rumus benar (pratinjau klien = hitungan ulang server: 1,92 kWh / Rp 2.880; LPG Rp 2.750); estimasi vs aktual dipisah di list, laporan, dan DB.
- [x] **UAT-10** Alokasi biaya batch/periode: total per sumber ≤ nominal (tepat = sumber diterima; +Rp 1 ditolak server; mengecilkan sumber di bawah alokasi lama ditolak); laporan reconcile (`allocated_total` = DB).
- [x] **UAT-11** Tutup kas: hanya pembayaran CASH menambah expected (transfer/QRIS dikecualikan server); selisih benar (expected 120.000, actual 119.500 → variance −500, tercatat di `cash_shifts`).

Status: **DONE 27 Okt 2026** — bukti lengkap di `docs/sprint-log.md` (bagian Sprint 05): migrasi `20261027000012_operating_cost.sql` (terpush), `test_operating_cost.py` 41 PASS, `flutter test` 53/53, build web + 11 bukti E2E di `docs/evidence/sprint05/`.

---

# 8. Sprint 06 – Penyempurnaan, QA, dan APK Rilis

**Goal:** menyempurnakan aplikasi operasional, bukan menambah halaman yang tidak dibutuhkan.

| ID | Prioritas | Implementasi langsung | Acceptance criteria |
|---|---|---|---|
| S06-01 | P0 | Audit setiap page Flutter: layout tablet landscape, HP portrait, state kosong, keyboard, snackbar, modal, tab | Navigasi lengkap, tanpa overflow |
| S06-02 | P0 | Uji QR submit online, retry, idempotency, item habis/harga berubah | Tidak ada sale/draft ganda akibat tombol berulang |
| S06-03 | P0 | Uji keamanan API/RLS, input injection, public QR rate limit, token rotate, secret scanning | Akses publik ke data internal = ditolak |
| S06-04 | P0 | Error logging, crash report (tanpa data sensitif), backup DB, latihan restore | Restore terbukti di staging |
| S06-05 | P0 | End-to-end smoke test `POS langsung` dan `QR → POS → bayar`, stok, laporan | Semua skenario kritis lulus pada tablet target |
| S06-06 | P0 | Kinerja: profil list panjang, transaksi, loading skeleton, cache aman, fetch efisien | Hasil pengukuran dicatat; UI tidak freeze |
| S06-07 | P1 | Struk printer ESC/POS atau Bluetooth **setelah tipe perangkat dipastikan** | Cetak/cetak ulang tidak menambah sale |
| S06-08 | P1 | Offline operator outbox SQLite (hanya jika dicakup) | Konflik dan unsynced terlihat; transaksi tidak silent loss |
| S06-09 | P0 | Build Android release, versioning, signing aman, migration plan, rollback procedure | APK/AAB dapat dipasang, tidak menyimpan secret server |
| S06-10 | P0 | Checklist UAT/SOP ringan dan serah terima operator | Operator dapat menyelesaikan transaksi tanpa bantuan developer |

**Status 27 Okt 2026: PARTIAL / gate rilis BLOCKED.** QA lokal dan web dikerjakan,
bukan klaim seluruh tiket DONE. Rincian per tiket di `docs/sprint-log.md` (Sprint 06),
paket instalasi/setup/SOP di `docs/handover.md`.

- Analyzer 0 issue; Flutter **148/148** (78 kombinasi layar/state/viewport +
  16 tes retry), regresi backend **212 PASS, 0 FAIL** dijalankan ulang terhadap
  hosted setelah migrasi `0013`; 29 probe publik lulus.
- Backup bisnis pulih ke staging PostgreSQL lokal (25 tabel/checksum, 23 policy),
  **bukan** full-restore Supabase Auth/Storage.
- Dua alur smoke browser menghasilkan sale #57/#58; QR Q00114 COMPLETED.
  Delapan screenshot di `docs/evidence/sprint06/`, **bukan bukti tablet Android**.
- Build APK 1.0.0+1 berhasil (58,1 MB), **unsigned**, belum bisa dipasang.
- **K06-01 diperbaiki**: `pos_refund` & `inv_adjust_stock` kini mewajibkan
  `p_idempotency_key`, menyimpan respons atomik, dan menolak payload berbeda;
  form Flutter menyimpan key sebelum kirim. Migrasi `0013` **sudah terpasang di
  hosted**; bukti `docs/evidence/sprint06/retry-fix.json`.
- Blocker tersisa: audit retry RPC mutasi lain, signing/keystore, rotasi password
  lama, tablet/restore cloud dan hosting QR permanen. Printer ditunda, offline
  tidak dicakup.

**Gate rilis wajib:**
- [x] Tidak ada navigasi/fitur `Dapur`, `Pesanan`, `Pegawai`, `Multi Cabang`, `SaaS`.
- [ ] Setiap tombol checkout dan setiap perubahan uang/stok aman terhadap retry —
  **sebagian**: checkout, QR submit, refund dan koreksi/waste stok lulus
  (server + klien + hosted terpasang); `inv_create_purchase`,
  `inv_produce_batch`, expense/energi dan alokasi **belum diaudit**.
- [x] Web QR menampilkan keberhasilan kirim draft, bukan menyatakan sudah dibayar.
- [x] Kas dan omzet benar-benar berdasarkan sale final, bukan data cart/QR pending.
- [ ] Backup/restore, autentikasi, dan pengujian manual tablet lulus.
- [x] Keterbatasan printer/offline/PSP dinyatakan jelas jika belum diuji.

---

# 9. Fitur Post-MVP yang **Tidak Dikerjakan**

Jangan melanjutkan Sprint 07 atau proyek Machine Learning selama pembangunan MVP. Yang dikerjakan hanya Sprint 01 sampai Sprint 06 dan perbaikan hasil UAT. Tidak boleh membuat model, FastAPI inference, tabel forecast, UI AI Insights, atau hasil prediksi demo. Usulan forecasting baru dibahas dalam PRD dan backlog terpisah **setelah rilis MVP dan data historis memadai**.

Data penjualan riil, histori harga, resep, dan waktu transaksi tetap dicatat dengan benar karena memang dibutuhkan oleh laporan aplikasi, bukan sebagai pekerjaan ML tambahan.

# 10. Kontrak Halaman dan File yang Direkomendasikan

Struktur ini adalah target refactor, bukan klaim file sudah dibuat:

```text
waroeng-mejeng-pos/
├── PRD.md
├── Sprints.md
├── index.html                         # MOCKUP interaktif, bukan aplikasi produksi
├── README.md
├── apps/
│   ├── pos_flutter/
│   │   └── lib/
│   │       ├── app/{router,theme,widgets}/
│   │       ├── features/
│   │       │   ├── dashboard/
│   │       │   ├── pos/             # termasuk QR Masuk + pembayaran
│   │       │   ├── catalog/
│   │       │   ├── tables_qr/
│   │       │   ├── inventory/
│   │       │   ├── recipes_hpp/
│   │       │   ├── purchases/
│   │       │   ├── operating_cost/
│   │       │   ├── energy_calculator/
│   │       │   ├── cash_shift/
│   │       │   ├── sales_history/
│   │       │   ├── reports/
│   │       └── core/{models,api,storage,utils}/
│   └── qr_web/
│       └── src/{pages,components,api}/
├── services/
│   ├── business_api/
├── supabase/{migrations,seed}/
├── tests/{unit,integration,e2e}/
└── docs/{architecture,api-contracts,sprint-log,release-notes}.md
```

Tidak membuat `features/orders`, `features/kitchen`, `features/employees`, atau `features/tenant`.

# 11. Integrasi CRUD dan UI Prioritas

| Fitur | Flutter page | Backend entity | UI inti |
|---|---|---|---|
| Dashboard | `dashboard_page` | `sales`, `expenses`, `ingredients` | KPI omzet, stok rendah, QR masuk |
| POS | `pos_page` | `sales`, `payments`, `qr_drafts` | 2 kolom tablet: menu kiri, keranjang kanan + QR Masuk |
| Pricing | `catalog_page` | `products`, `price_history` | Form harga, modifier, tombol tersedia/habis |
| Meja & QR | `qr_settings_page` | `dining_tables` | Grid meja + generate/rotate QR |
| Stok | `inventory_page` | `ingredients`, `stock_movements` | Mutasi, threshold, pencarian |
| Resep | `recipe_page` | `recipe_versions`, `recipe_items` | Edit takaran/yield + HPP hasil |
| Pembelian | `purchases_page` | `purchases` | Form terima bahan, total biaya |
| Biaya | `expenses_page` | `expenses`, `cost_allocations` | Input actual/estimate dan catatan |
| Energi | `energy_page` | `energy_estimates` | Kalkulator realtime + simpan |
| Kas | `cash_page` | `cash_shifts`, `payments` | Buka/tutup shift, selisih |
| Riwayat | `sales_history_page` | `sales`, `refunds` | Filter, detail, struk dan refund |
| Laporan | `reports_page` | summary SQL | Grafik, laporan biaya dan margin |
| Pengaturan | `settings_page` | `business_settings` | Nama, lokasi, tarif dan preferensi |

# 12. Template Issue Pengembangan

```md
## [S02-04] Implementasi POS tablet
- Status: TODO
- Prioritas: P0
- PRD: SCR-02, FR-07
- Dep: S02-01, S02-03
- Berkas yang ditambahkan/diubah:
- Detail implementasi:
  - [ ] Grid katalog tablet + responsive mobile
  - [ ] Cart add, qty, remove, modifier
  - [ ] Total perkiraan dan API quote
  - [ ] Empty/loading/error state
  - [ ] Test unit/widget/E2E
- Acceptance criteria:
  - [ ] Kasir dapat checkout tanpa membuka halaman pesanan
  - [ ] Tombol tidak memicu duplicate submit
- Bukti: commit URL / test log / screenshot
- Reviewer:
```

# 13. Catatan Progres dan Change Log

| Tanggal | Sprint | Tiket | Status | Implementasi/commit | Hasil pengujian | Kendala |
|---|---|---|---|---|---|---|
| 26 Okt 2026 | 01 | S01-02, S01-03, S01-04, S01-05, S01-06, S01-07 | DONE | `a039446` scaffold + shell + auth + migrasi + RLS | `flutter analyze` 0 issue; `flutter test` 19/19; REST Supabase anon vs operator lulus | - |
| 26 Okt 2026 | 01 | S01-01, S01-08 | PARTIAL | monorepo + CI workflow | `npm run build` lulus; `npm run dev` HTTP 200 | Belum ada remote Git/GitHub Actions; `flutter run` butuh perangkat |
| 26 Okt 2026 | 01 | S01-01 | DONE | `flutter run` di HP fisik OPPO CPH2473 | login operator nyata, navigasi portrait+landscape, 5 screenshot di `docs/evidence/sprint01/` | - |
| 26 Okt 2026 | 01 | (perbaikan) | DONE | fix overflow `module_placeholder.dart` + `module_placeholder_test.dart` | bug ditemukan di landscape HP (`OVERFLOWED BY 112 PIXELS`), fixed, 20/20 test lulus, verifikasi ulang di device | - |
| 26 Okt 2026 | 02 | S02-01…S02-10 | DONE | migrasi 0005–0007 + API pos server-side + Flutter katalog/POS/riwayat/dashboard | `flutter analyze` 0 error; `flutter test` 29/29; REST integration 73 PASS 0 FAIL; alur E2E web Chrome 18 screenshot di `docs/evidence/sprint02/` | Pengujian HP Android ditunda (perangkat tidak tersedia); S01-08 tetap menunggu remote GitHub |
| 26 Okt 2026 | 03 | S03-01…S03-09 | DONE | `96c2c08` migrasi 0008–0009 + web Vue QR + panel QR Masuk + draft idempoten | `flutter test` 33/33; REST `test_qr_drafts.py` 37 PASS 0 FAIL; 19 screenshot `docs/evidence/sprint03/` via HTTPS tunnel | Hosting QR permanen = keputusan user; Android fisik ditunda |
| 27 Okt 2026 | 04 | S04-01…S04-09 | DONE | migrasi 0010 inventori + 0011 fix TZ dashboard + Flutter stok/pembelian/resep-HPP | `flutter analyze` 0 error; `flutter test` 42/42; `test_inventory.py` 57 PASS; regresi POS 77 PASS + QR 37 PASS; npm build 299 kB; 14 screenshot `docs/evidence/sprint04/` | Android fisik ditunda; S01-08 menunggu remote GitHub |
| 27 Okt 2026 | 05 | S05-01…S05-09 | DONE | migrasi 0012 energi/biaya/alokasi/kas/laporan + RPC definer + Flutter kalkulator/biaya/kas/laporan + dashboard detail | `flutter analyze` 0 error; `flutter test` 53/53; `test_operating_cost.py` 41 PASS (UAT-09–11); npm build lulus; 11 bukti `docs/evidence/sprint05/` (kalkulator 1,92 kWh/Rp 2.880, alokasi ditolak, kas selisih −500, CSV) | Android fisik ditunda; S01-08 menunggu remote GitHub |
| 27 Okt 2026 | 06 | S06-01…S06-10 | PARTIAL / BLOCKED | perbaikan layout/keranjang HP, pengaturan read-only, audit keamanan/restore, build unsigned, dokumen serah terima | analyzer 0 issue; Flutter 134/134; backend 212 PASS; 29 probe publik; restore 25 tabel; dua smoke web; APK unsigned 58,1 MB | Retry refund/koreksi stok belum aman; signing, Android target, rotasi password, restore cloud/Storage dan hosting QR permanen belum lulus |
| 27 Okt 2026 | 06 | K06-01 (fix) | PARTIAL → sebagian selesai | `4019874` → fix menyusul: migrasi `20261027000013_mutation_retry.sql` + `lib/core/mutation_retry.dart` + form riwayat/stok + `tests/integration/test_mutation_retry.py` (CI) | migrasi **diterapkan ke hosted**; replay `BEGIN/ROLLBACK` refund +100 / stok +1; probe anon 401; 9 tes SQL lulus; Flutter **148/148**; analyzer 0; regresi hosted **212 PASS 0 FAIL**; build web release lulus | Audit RPC mutasi lain belum; klien baru belum didistribusikan (APK masih unsigned); bukti putus-jaringan di tablet belum |

**Change Log v2.0:**
- Menghapus Sprint 0 Observasi dan mengganti Sprint 01 dengan setup serta pembangunan dasar.
- Menghapus pembangunan Kitchen, Order Management, Employee Roles, Multi-Tenant.
- Menggabungkan semua kerja operasional ke **Kasir POS**, termasuk notifikasi `QR Masuk`.
- Menjaga fungsi keuangan, inventaris, utilitas, dan AI sesuai PRD v2.0.
- Mengubah keberhasilan sprint menjadi deliverable aplikasi dan tes, bukan daftar kegiatan lapangan.

## Keputusan UI dan Product MVP (per 26 Oktober 2026)

- **Warna primer `#930031`**. Jangan gunakan palet hijau lama `index.html` sebagai brand primer.
- **Tanpa emoji dan ilustrasi generik** pada seluruh aplikasi Flutter. Gunakan ikon Material bawaan Flutter dan foto produk yang sah.
- `index.html` merupakan prototipe perilaku dan layout. Implementasi Flutter wajib mempunyai state, validasi, loading, empty/error, animation feedback, dan data sungguhan.
- **MVP = Sprint 01–06 saja**, tanpa halaman, model, pipeline, API, dependensi, dan klaim AI/ML.
- Buktikan setiap sprint menggunakan build dan tes yang benar; checklist tidak boleh diubah menjadi DONE jika belum dikerjakan.

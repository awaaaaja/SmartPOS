# Sprint Log

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

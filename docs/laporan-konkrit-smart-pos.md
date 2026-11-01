# LAPORAN KONKRIT — Smart POS "Waroeng MeJeng Kampoeng"

> **Dokumen:** laporan teknis–operasional menyeluruh untuk seluruh repository
> `SmartPOS`, target implementasi nyata: **Waroeng MeJeng Kampoeng** (warung
> makan satu operator, satu meja/kasir, QR menu pelanggan).
> **Tanggal laporan:** 1 November 2026 · **Basis:** `origin/main` @ `9759ef5`
> · PRD v2.1 · plan eksekusi `docs/plan-qr-wizard-notif.md` v4 (seluruh bagian
> selesai).
>
> Laporan ini menjawab: (1) apa saja fitur dan bagaimana alurnya, (2) bagaimana
> HPP dan kalkulator listrik/LPG dihitung sampai rumus terakhir, (3) bagaimana
> implementasi ML-nya — dari lapisan data sampai loop evaluasi otomatis, dan
> (4) di mana seluruh dokumen `md` pendukung berada.

---

## Daftar Isi

1. [Ringkasan eksekutif](#1-ringkasan-eksekutif)
2. [Sasaran: Waroeng MeJeng Kampoeng](#2-sasaran-waroeng-mejeng-kampoeng)
3. [Arsitektur & stack teknologi](#3-arsitektur--stack-teknologi)
4. [Model data, keamanan, dan aturan uang](#4-model-data-keamanan-dan-aturan-uang)
5. [Fitur & alur lengkap per modul (5.1–5.18)](#5-fitur--alur-lengkap-per-modul)
6. [Implementasi ML — dari fitur sampai model otomatis](#6-implementasi-ml--dari-fitur-sampai-model-otomatis)
7. [Pengujian, CI/CD, dan operasi](#7-pengujian-cicd-dan-operasi)
8. [Peta dokumen Markdown repository](#8-peta-dokumen-markdown-repository)
9. [Status, temuan, dan rekomendasi lanjutan](#9-status-temuan-dan-rekomendasi-lanjutan)

---

# 1. Ringkasan eksekutif

**Smart POS** adalah sistem point-of-sale MVP *satu operator* yang terdiri dari
tiga bagian yang saling terhubung di satu database Postgres (Supabase):

| Bagian | Teknologi | Peran | Rilis |
|---|---|---|---|
| Aplikasi kasir | **Flutter** (Android, prioritas tablet landscape) | Seluruh operasi operator: POS, katalog, stok, HPP, biaya, laporan | 21 file test, **195 test lulus** |
| Menu pelanggan | **Vue 3 + Vite** di GitHub Pages | Wizard pesanan 3 langkah dari QR meja (`awaaaaja.github.io/SmartPOS/`) | vitest **21**, e2e Playwright **6** |
| Backend | **Supabase** (Auth + PostgreSQL) | Sumber kebenaran tunggal: uang, stok, status; 19 migrasi SQL | integrasi **245 cek lulus** terhadap hosted + 3 suite di CI |

**Angka verifikasi terkini (1 Nov 2026):**

- Suite Flutter: **195/195**, `flutter analyze` **0 issue**.
- Test integrasi terhadap database hosted: `test_pos_api` **77**, `test_inventory` **57**, `test_operating_cost` **41**, `test_qr_drafts` **70** → **245 PASS, 0 FAIL**.
- Tiga suite lagi (`test_mutation_retry` 19, `test_settings_edit` 4, `test_analytics_views` 8) berjalan otomatis di job CI `migrations` pada Postgres polos (`postgres:15`).
- CI 4 job hijau; Deploy Pages sukses; wizard QR live.
- Migrasi `0018` (preferensi bayar + identitas) dan `0019` (siklus hidup pesanan) **live di hosted** dan tercatat di `supabase_migrations.schema_migrations`.

**Prinsip desain yang membedakan sistem ini (dan menjadi benang merah seluruh laporan):**

1. **Uang selalu integer Rupiah** — tidak ada float untuk uang, di klien maupun server.
2. **Server menghitung ulang semuanya** — klien hanya mengirim keranjang mentah; total, diskon, pajak, kembalian, HPP, biaya energi dihitung Postgres.
3. **Idempotency tiga lapis** — `sales.idempotency_key`, `(table_id, client_key)` untuk draft QR, dan `mutation_requests` + advisory lock untuk mutasi berisiko (refund, stok, pembelian, energi).
4. **Label jujur** — ESTIMATED ≠ ACTUAL, HPP disebut estimasi, margin disebut "bukan laba bersih", data kosong ditampilkan kosong (bukan angka pura-pura).
5. **WIB eksplisit** — setiap batas hari/jam dihitung `at time zone 'Asia/Jakarta'`, perbaikan bug zona 7 jam sudah dimigrasi (0011).
6. **Tanpa ML di klien** — klien hanya membaca angka; seluruh logika prediktif ada di server (lihat §6).

---

# 2. Sasaran: Waroeng MeJeng Kampoeng

**Profil pengguna final (PRD v2.1):**

- **Satu operator** memegang seluruh aplikasi: kasir, dapur (dalam alur tunggal POS), pembelian, biaya, laporan. Tidak ada role, tidak ada modul Dapur/Kitchen Display terpisah, tidak ada multi-cabang.
- **Pelanggan** hanya lewat QR meja → web menu → kirim pesanan. Tanpa aplikasi, tanpa akun.
- **Perangkat:** tablet Android landscape sebagai kasir utama; HP operator sebagai cadangan (bottom navigation 6 tab: Beranda, Kasir, Pesanan, Stok, Laporan, Lainnya).

**Alur operasional harian yang didukung penuh:**

```text
Buka shift (hitung kas awal)
  → layani pelanggan: kasir manual ATAU pesanan QR masuk
      (draft → Diterima → Diproses → Selesai → Bayar)
  → katalog/ harga/ arsip dikelola saat sela
  → stok terpotong otomatis saat bayar (resep) / saat produksi batch
  → catat pembelian, koreksi/waste, biaya listrik & LPG, biaya lain
  → tutup shift: hitung fisik → selisih tercatat
  → laporan tanggal → ekspor CSV → (Fase ML) estimasi kebutuhan bahan
```

**Ruang lingkup yang sengaja DIKECUALIKAN** (keputusan terdokumentasi di
`docs/decision-log.md` dan PRD): multi-user/role, integrasi QRIS otomatis/PSP
(MVP: QRIS verifikasi manual), printer thermal khusus (memakai share sheet
OS), offline-sync penuh, otomasi pembelian, dan profil pelanggan/segmentasi.

---

# 3. Arsitektur & stack teknologi

```text
┌────────────────────────────┐        ┌─────────────────────────────┐
│  apps/pos_flutter (kasir)  │        │  apps/qr_web (pelanggan)    │
│  Flutter · Riverpod v3     │        │  Vue 3 · Vite 7 · JS        │
│  supabase_flutter 2.18     │        │  @supabase/supabase-js 2    │
│  build: --dart-define      │        │  deploy: GitHub Pages       │
│  QR_WEB_URL=…/SmartPOS/    │───────▶│  /SmartPOS/?token=<token>   │
└─────────────┬──────────────┘        └──────────────┬──────────────┘
              │ authenticated (JWT operator)        │ anon (token QR saja)
              ▼                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Supabase: Auth · PostgREST · Storage (bucket product-photos)        │
│ PostgreSQL — 19 migrasi: RLS operator_only + RPC SECURITY DEFINER   │
│   • baca: SELECT tabel via RLS is_operator()                        │
│   • tulis/hitung: HANYA lewat RPC (pos_*, inv_*, qr_*, exp_*, …)    │
│   • anon: hanya get_public_menu + qr_submit_draft                   │
└─────────────────────────────────────────────────────────────────────┘
```

**Dependensi utama Flutter** (`pubspec.yaml`): `flutter_riverpod 3.4.3`,
`supabase_flutter 2.18.3`, `intl` (format Rupiah id-ID), `qr_flutter` (QR
meja), `share_plus` (cetak/bagikan QR & CSV), `audioplayers` (nada notifikasi
pesanan), `url_launcher` (WhatsApp penagihan), `image_picker` (foto menu),
`shared_preferences` (token QR perangkat, mutasi tertunda, preferensi suara).
**Tanpa** paket `printing`, `pdf`, `charts`, zona-waktu — WIB dihitung manual
(`wibOffset = Duration(hours: 7)` di `lib/core/formatters.dart`), sehingga
perilaku deterministik di seluruh unit test.

**Dependensi web QR**: hanya `vue` + `supabase-js` (dev: vite, vitest,
jsdom). Tanpa router, tanpa state library — satu `App.vue` 646 baris dengan
wizard 3 langkah, CSS tulis tangan 438 baris (token brand `#930031`).

**Alur data QR end-to-end:**

```text
Operator buat meja  →  qr_create_table → token plaintext (sekali tampil)
  →  disimpan di perangkat (SharedPreferences) + dicetak/dibagikan
  →  server hanya simpan sha256(token) + token_version
Pelanggan scan  →  https://…/SmartPOS/?token=…
  →  get_public_menu(token)  [SECURITY DEFINER, anon]
  →  wizard 3 langkah  →  qr_submit_draft(items, preferensi, identitas)
  →  draft PENDING (harga snapshot server, idempoten per client_key)
  →  Tab Pesanan: Diterima (klaim) → Diproses → Selesai → Bayar
  →  checkout POS menghasilkan sale final  →  sale_id menutup draft
  →  stok resep terpotong otomatis (trigger AFTER INSERT payments)
```

---

# 4. Model data, keamanan, dan aturan uang

## 4.1 Peta 19 migrasi (urut)

| # | File | Isi inti |
|---|---|---|
| 0001 | `init_schema` | `business_settings` (juga menyimpan `operator_email` = jangkar identitas), `product_categories`, `products`, `product_price_history` (trigger otomatis saat harga berubah), `modifiers`, `product_modifiers`, `dining_tables` (`qr_token_hash` unik, `token_version`) |
| 0002 | `rls` | Fungsi `is_operator()` (email JWT ↔ `business_settings.operator_email`) + policy `operator_all` di 7 tabel; **anon tanpa policy = tertutup total** |
| 0003 | `public_menu_api` | `hash_table_token` (sha256) + `get_public_menu` → JSON menu (hanya produk aktif, kategori berisi produk, foto, modifier) — grant **anon** |
| 0004 | `fix_pgcrypto_search_path` | Kualifikasi `extensions.digest` agar idempoten di CI Postgres polos |
| 0005 | `sales` | `sales` (status FINAL/PARTIALLY_REFUNDED/REFUNDED, `idempotency_key` unik, uang int), `sale_items` (snapshot nama+harga+modifier), `payments` (CASH/TRANSFER/QRIS), `refunds`, `audit_events` |
| 0006 | `pos_api` | `pos_line_total`, `pos_quote`, `pos_checkout`, `pos_sale_receipt`, `pos_refund`, `pos_dashboard_summary` — semua perhitungan uang di sini |
| 0007 | `product_photos` | Bucket publik `product-photos` + policy baca publik/tulis operator |
| 0008 | `qr_drafts` | Tabel draft + item, `qr_submit_draft` (anon, rate limit 5/10 menit, idempoten), `qr_list_drafts`, `qr_claim_draft`, `qr_cancel_draft`, `qr_complete_draft`, kedaluwarsa 2 jam |
| 0009 | `table_qr_api` | `qr_create_table`, `qr_rotate_token` — token acak 16 byte, plaintext hanya sekali, rotasi menaikkan `token_version` (QR lama mati seketika) |
| 0010 | `inventory` | `ingredients` (`base_unit` g/ml/pcs terkunci, `unit_cost`, `balance`), `stock_movements` (append-only + trigger anti-UPDATE/DELETE), `purchases`, `recipe_versions`/`recipe_items`, `stock_mode` RECIPE/BATCH, `production_batches`, trigger potong stok saat bayar, `inv_hpp` |
| 0011 | `dashboard_tz_fix` | Perbaikan batas "hari ini" WIB (bug 7 jam: `date_trunc` naive → `at time zone` ganda) |
| 0012 | `operating_cost` | `expenses` (ACTUAL/ESTIMATED), `energy_estimates`, `cost_allocations`, `cash_shifts` (indeks parsial: maksimal 1 shift OPEN), `energy_save_estimate`, `cost_allocate`, `cash_shift_*`, **`pos_reports`** |
| 0013 | `mutation_retry` | Tabel `mutation_requests` (PK operation+key, RLS tertutup), pola `*_once` + wrapper idempoten (`pg_advisory_xact_lock`), perbaikan tanda-turunan `inv_adjust_stock` |
| 0014 | `mutation_retry_rest` | Perluas ke 6 operasi: `pos_refund`, `inv_adjust_stock`, `inv_create_purchase`, `inv_produce_batch`, `exp_save`, `energy_save_estimate`; helper `mutation_run_once` |
| 0015 | `operator_guard` | Pola keamanan inti: **19 fungsi di-rename `*_impl` + grant dicabut**, dibuat wrapper bertanda tangan sama yang cek `is_operator()` → `42501 operator_required` |
| 0016 | `settings_edit` | `settings_save` — validasi nama/alamat/zona waktu (`pg_timezone_names`)/tarif 0–1 + audit before/after |
| 0017 | `analytics_aggregates` | **5 view agregat** (fondasi ML, §6) + 2 index; `security_invoker=true` |
| 0018 | `qr_payment_pref` | Kolom `pay_intent`, `pay_method`, `customer_name`, `customer_phone`; `qr_submit_draft` 7 parameter (4 `DEFAULT NULL` → klien lama tetap sah); `qr_draft_json` +preferensi |
| 0019 | `qr_order_lifecycle` | Status `PREPARING`, `qr_mark_preparing`, `qr_complete_draft` 4 cabang (`p_sale_id DEFAULT null`), cancel dari PREPARING, `qr_list_drafts` = papan aktif |

## 4.2 Model keamanan (bertingkat)

1. **Identitas** = satu baris `business_settings(id=1).operator_email`. Fungsi `is_operator()` membandingkan `auth.jwt()->>'email'` (case-insensitive). Tidak ada tabel user/role internal.
2. **RLS**: tabel privat memakai `operator_all` (SELECT+INSERT+UPDATE+DELETE untuk authenticated yang lolos `is_operator()`) atau `operator_read` (SELECT saja — inventori & operasional; tulis hanya lewat fungsi definer). `qr_drafts` dan `mutation_requests` **tanpa policy** = hanya fungsi definer yang menyentuh.
3. **Sejak migrasi 0015**, *setiap* RPC yang bisa dipanggil klien dibungkus wrapper `is_operator()`; badan asli `*_impl` tidak punya grant sama sekali — menutup celah di mana akun authenticated non-operator bisa memanggil fungsi definer lama lewat PostgREST.
4. **Anon** hanya mengenal dua fungsi: `get_public_menu(token)` dan `qr_submit_draft(token, …)`. Keduanya tidak pernah mengekspos data selain menu aktif / konfirmasi draft miliknya sendiri.
5. **Service role key tidak pernah** ada di repo, klien Flutter, maupun web — hanya untuk operasi server/CI. `Kredensial.md` dan `.env.local` masuk `.gitignore`.
6. **Audit** — semua operasi menulis `audit_events` (entity, action, detail, pelaku): CHECKOUT, REFUND, CLAIM, PREPARE, SAVE, UPDATE settings, dst. Menjadi jejak forensik dan bahan evaluasi ML fase lanjut.

## 4.3 Aturan uang (dikutip persis dari SQL)

- **Baris:** `line_total = (harga dasar + Σ price_delta modifier terpilih) × qty`, qty 1–99, modifier valid terhadap produk (`max_select`).
- **Kuotasi** (`pos_quote`):
  ```text
  diskon  = round(subtotal × diskon_persen / 100)
  pajak   = round((subtotal − diskon) × tax_rate)        -- fraksi dari settings
  layanan = round((subtotal − diskon) × service_rate)
  total   = subtotal − diskon + pajak + layanan
  ```
- **Checkout** (`pos_checkout`): klien kirim `p_paid` → server tolak bila kurang (`insufficient_payment`), `kembalian = paid − total`, nomor struk `MJ-YYMMDD-####` (sequence), snapshot item, insert `payments` **memicu trigger pemotongan stok resep secara atomik dengan checkout**. Replay kunci yang sama → struk yang sama + `idempotent_replay: true` (tidak ada transaksi ganda).
- **Refund** (`pos_refund`): kunci baris `FOR UPDATE`, `refund_amount + amount ≤ total`, status jadi `PARTIALLY_REFUNDED`/`REFUNDED`, uang histori tidak pernah dihapus, refund **tidak** mengembalikan stok (kebijakan: koreksi stok manual lewat ADJUSTMENT/WASTE dengan alasan).

---

# 5. Fitur & alur lengkap per modul

> Setiap sub-bagian memuat: **apa yang dilihat operator → alur langkah-demi-langkah →
> RPC/pemrosesan server → kasus tepi yang ditangani → file sumber**.

## 5.1 Gerbang login & shell aplikasi

- **Alur:** `LoginPage` → `AuthRepository.signIn(email, password)` → Supabase Auth → `AuthGate` berpindah ke `AppShell`.
- **Shell** (`lib/app/shell.dart`): lebar ≥840px = **sidebar** 14 tile (13 modul lama + tab **Pesanan** baru), lebar <840px = **NavigationBar** 5 tab + tombol **Lainnya** (daftar modul tersisa). Destinasi terpilih disimpan pada `selectedDestinationProvider` **global** — bukan state privat shell — sehingga banner notifikasi dan tombol `[Bayar]` bisa memindah tab dari mana pun.
- **Badge Pesanan:** `_PendingOrdersBadge` memegang `qrDraftsProvider` sendiri (refresh 10 detik hanya membangun ulang lencana, bukan seluruh shell) dan menghitung **hanya draft PENDING** ("pesanan baru ≠ antrean aktif").
- **Keluar:** tombol `Keluar` memanggil `signOut` (dites).
- **Uji:** `test/app/shell_test.dart` (7 test: sidebar, pindah modul, nav 6 item, sign-out, badge PENDING, banner `[Lihat]` → tab Pesanan, polling tidak me-reset pencarian POS), `page_layout_test.dart` (14 halaman × viewport × state), `theme_test.dart`, `qr_inbox_watcher_test.dart`.

## 5.2 Dashboard

- **Kartu utama** (dari `pos_dashboard_summary`): *Omzet hari ini* = `Σ(total − refund_amount)` dengan batas hari WIB benar (`created_at >= (date_trunc('day', now() at tz 'Asia/Jakarta') at tz 'Asia/Jakarta')`, tanpa baris `REFUNDED`), *Transaksi hari ini*, *Refund hari ini*, plus *Sepanjang masa*.
- **Kartu detail** (dari `pos_reports(hari ini)`): biaya bahan (HPP resep, estimasi), biaya aktual, overhead estimasi, dan **"Estimasi hasil operasi hari ini"** = `net_sales − hpp_ingredient_cost − expenses_actual_period` — diberi disclaimer tegas *"bukan pernyataan laba bersih"* (belum termasuk tenaga kerja, susut, pajak).
- **Grid responsif**: 3/2/1 kolom pada lebar ≥1000 / ≥560 / <560 px (perbaikan overflow tablet landscape).
- **Catatan jujur di header:** draft QR yang belum dibayar tidak dihitung sebagai omzet.

## 5.3 Kasir POS (jantung operasi)

- **Layout:** lebar ≥720dp = katalog (kiri) + keranjang (kanan); di bawah itu keranjang jadi bottom sheet dengan jumlah baris. Pencarian di-debounce 250 ms (satu setState per jeda, bukan per huruf).
- **Alur transaksi:**
  1. Cari/pilih kategori → ketuk produk → sheet varian: pilih modifier (aturan `min_select`/`max_select`), qty (tombol −/+), catatan → **Tambah · Rp X**.
  2. Keranjang: edit qty inline, hapus baris, diskon %, pilih meja/takeaway, jenis bayar (Tunai/Transfer/QRIS), nominal diterima → kembalian live (*pratinjau saja*).
  3. **Bayar** → `_PaymentSheet` membuat **idempotency key sekali per percobaan bayar** (`pos-<millis>-<8hex>`) yang dipakai ulang saat retry → `pos_checkout` server.
  4. Server menghitung ulang total, menolak pembayaran kurang, memotong stok resep (trigger), mengembalikan struk.
  5. Klien: bersihkan keranjang → **`QrClaimService.completeClaimed(saleId)`** melunasi **semua** draft QR yang menopang keranjang perangkat ini (set dikosongkan — invarian C1.2: draft terklaim pasti masih di keranjang karena checkout selalu menghabiskan set) → dialog struk (bagikan/cetak via share sheet).
- **Kasus tepi:** stok tidak cukup → `insufficient_stock` berisi nama bahan; produk diarsipkan hilang dari grid; timeout jaringan → mode "ulangi transaksi yang sama" dengan kunci lama (tidak duplikasi).
- **Uji:** `cart_state_test`, `pos_mobile_test` + 77 cek integrasi `test_pos_api.py` (23+ skenario uang: diskon, pajak, layanan, kembalian, replay, refund ganda, dll.).

## 5.4 Riwayat penjualan & refund

- **Daftar:** 100 terbaru, pencarian no. struk, chip status (Final / Refund sebagian / Refund penuh), metode ikut tampil, nilai akhir = `total − refund_amount`.
- **Struk** (`pos_sale_receipt`): snapshot item + modifier, subtotal/diskon/pajak/layanan/metode/diterima/kembalian, riwayat refund (jumlah + alasan).
- **Refund:** dialog mengunci `amount ≤ total − refund`, alasan ≥3 char, lewat `MutationRetryStore` (kunci idempoten per `sale_id`) → setelah sukses seluruh provider terkait (dashboard, laporan, kas shift) di-invalidate. Refund penuh mengubah status REFUNDED; refund sebagian → PARTIALLY_REFUNDED.

## 5.5 Menu & Harga (katalog)

- CRUD produk (nama, kategori, harga, aktif, `stock_mode` RECIPE/BATCH), **foto** ke bucket `product-photos` (9 foto menu sudah dipakai; 2 kandidat sengaja **dilewati karena lisensi/watermark** — aturan `Prompt.md`), modifier produk (nama, selisih harga, min/max pilih).
- **Riwayat harga otomatis** — trigger `trg_products_price_history` mencatat setiap perubahan harga beserta pelaku (`auth.uid()`). Riwayat ini nanti menjadi **fitur harga untuk model forecast** (§6).
- **Arsip** (Fase D, tanpa migrasi): `archived_at` di-set via RLS operator; provider terpisah `catalogProductsProvider`/`catalogCategoriesProvider` (`includeArchived=true`) **hanya** untuk halaman katalog dengan chip filter **Aktif | Arsip**; tombol keluar-arsip mengembalikan `archived_at = null`. POS dan menu web tetap memakai provider tanpa arsip — perilaku lama tidak berubah.
- Kategori kosong/produk terarsip tidak pernah muncul di menu publik.

## 5.6 Meja & QR

- **Tambah meja** → `qr_create_table(label)` → server menghasilkan token acak 16 byte, menyimpan **sha256** saja, mengembalikan plaintext **sekali kali** → disimpan perangkat (`TableTokenStore`, JSON di SharedPreferences) → dialog QR (200–240px), URL `…/SmartPOS/?token=…`, tombol **Salin** dan **Cetak/Bagikan** (`RepaintBoundary` → PNG pixelRatio 3 → share sheet OS).
- **Rotasi token** → QR lama mati seketika (`token_version` naik), token baru tampil sekali dan menimpa penyimpanan lokal.
- **Aktif/nonaktif** meja → `is_enabled` (QR dinonaktif → `invalid_table_token` di pelanggan).
- **Risiko yang terdokumentasi:** siapa pun yang memegang URL = bisa membuka menu; setara kertas QR yang tercetak. Rotasi adalah mitigasi utamanya.

## 5.7 Web menu QR — wizard 3 langkah

- **Langkah 1 "Mulai":** pilih niat bayar — **Bayar sekarang (default)** atau **Open Bill** — plus identitas **opsional** (Nama ≤60 char; No. WA 8–20 digit dari karakter `0-9 + - spasi`, divalidasi klien). Data identitas **tidak pernah disimpan ke localStorage** (hanya `qr_client_key` yang disimpan — diuji eksplisit di vitest).
- **Langkah 2 "Pilih menu":** chip kategori sticky (Semua/Makanan/Minuman), kartu produk **dengan foto**, sheet varian (aturan min/max agregat, catatan per baris), bar keranjang sticky (jumlah + subtotal), bottom sheet keranjang (qty +/−; qty 0 menghapus baris).
- **Langkah 3 "Pembayaran":** ringkasan, kartu metode (CASH/QRIS/Transfer) **hanya untuk PAY_NOW**, rekap identitas, tombol kirim.
- **Submit:** `qr_submit_draft` dengan **hanya** `{product_id, qty, modifier_ids, note}` per item — **tanpa harga** (server snapshot harga saat itu). Klien idempoten: `qr_client_key` dibuat sekali (`crypto.randomUUID()`), **dipertahankan saat gagal** (retry = draft yang sama), **dirotasi setelah sukses** (pesanan berikutnya = draft baru).
- **Konfirmasi:** referensi `Qxxxxx`, item, subtotal, meja, niat·metode·nama, dan pernyataan tegas **"Pesanan belum dibayar"** + instruksi tunjukkan referensi ke kasir. Tombol **"Pesan lagi"** mengosongkan identitas/metode/kategori (reset privasi) dan kembali ke langkah 1.
- **Pesan error manusiawi:** `rate_limited` → "Terlalu sering…", `invalid_table_token` → **"QR tidak valid"**, `product_unavailable` → "tidak tersedia", jaringan → kartu coba lagi.
- **Uji:** vitest 21 (argumen RPC persis, rotasi key, Open Bill kirim `p_pay_method:null`, validasi modifier, privasi) + e2e Playwright 6 (semua RPC di-mock via `page.route`, tanpa DB).

## 5.8 Tab Pesanan — siklus hidup pesanan QR (Fase C)

- **Papan aktif** dari `qr_list_drafts()` (migrasi 0019): `PENDING`, `CLAIMED`, `PREPARING`, dan `COMPLETED` yang **belum dibayar** (`sale_id IS NULL`), urut `created_at`. Empat seksi tampil: **Baru masuk · Diterima · Diproses · Selesai — belum bayar**.
- **Aksi per status (tabel §C3):**

  | Status | Aksi | Server |
  |---|---|---|
  | PENDING | **Diterima** / **Batalkan** | klaim atomik (`qr_claim_draft`: `WHERE status='PENDING' AND expires_at >= now()` — kalah = `draft_not_claimable`); cancel |
  | CLAIMED | **Diproses** / **Bayar** / **Batalkan** | `qr_mark_preparing` (baru, audit PREPARE); bayar; cancel |
  | PREPARING | **Tandai selesai** / **Bayar** / **Batalkan** | `qr_complete_draft(id, null)` → "Selesai, belum bayar"; bayar; cancel (0019 mengizinkan cancel dari PREPARING) |
  | COMPLETED (belum bayar) | **Bayar** | pelunasan nanti mengaitkan sale |

- **Semantik `qr_complete_draft` 4 cabang** (0019): CLAIMED/PREPARING → COMPLETED dengan `sale_id` boleh null; COMPLETED-sale-null + `p_sale_id` → **kaitkan pelunasan** (Open Bill); COMPLETED + sale sama → idempoten; selain itu → `draft_not_completable`. **Uang tidak berubah** — total final tetap dari keranjang saat checkout.
- **[Diterima] (klaim):** `QrClaimService.claimDraft` — refresh harga katalog dulu; snapshot ≠ harga kini → **dialog Konflik harga** (daftar per baris + item tak tersedia dilewati); setujui → pakai harga terkini; PENDING → klaim atomik di server dulu (gagal = kemungkinan sudah diambil operator lain → SnackBar jujur); status lain → lanjut lokal (sudah pernah diambil). Item masuk keranjang + id tercatat di `claimedDraftIdsProvider` (global).
- **[Bayar]:** `payDraft` = pastikan draft ada di keranjang (tanpa duplikasi bila sudah di-set) → pindah tab **Kasir POS** — keranjang tetap bisa disesuaikan sebelum checkout.
- **[Hubungi WA]:** `core/wa_link.dart` — `normalizeWaPhone` (menerima `+62/62/0/8`, buang spasi/tanda baca; ditolak bila bukan 11–16 digit setelah konversi), `waMessageUrl` → `https://wa.me/<norm>?text=…`, pesan prabayar: *"Halo {nama}, pesanan Anda di {meja} ({ref}) sudah selesai namun belum dibayar. Silakan lakukan pembayaran di kasir. Terima kasih 🙏"*. Nomor tidak valid → tombol **nonaktif** + tooltip "Nomor WA tidak valid". Gagal membuka WhatsApp bukan penghalang operasi.
- **Lencana kartu:** SUDAH BAYAR (hijau, dari `sale_id`) / BELUM BAYAR (kuning); baris identitas `nama · WA …`; chip preferensi dari wizard (**Bayar sekarang · QRIS**, **Buka bill**, dst.); catatan jujur *"Total akhir = keranjang saat bayar (bisa bertambah)"*.
- **Notifikasi (Fase B):** `QrInboxWatcher` di shell — **polling 10 detik satu-satunya** di seluruh aplikasi, muat pertama = **baseline sunyi** (draft lama tidak diumumkan ulang), draft PENDING baru → SnackBar *"Pesanan baru dari Meja 3 · Q00042"* + aksi **[Lihat]** (pindah tab Pesanan) + **nada** (4 nada Kenney *Interface Sounds* CC0 di `assets/sounds/`, bisa mati/ubah nada/pratinjau di Pengaturan, volume default 0.8). Pemutar lewat seam `notifSoundPlayer` (test tanpa audio); prefs `SharedPreferencesAsync` yang tidak tersedia → default tanpa exception.
- **Uji:** `orders_inbox_page_test` (14), `claimed_drafts_provider_test` (3: lunasi semua id + set terkuras, set kosong tanpa RPC, gagal kait tidak melempar), `shell_test` badge/banner/polling, `qr_inbox_watcher_test` (3) + **70 cek integrasi** siklus hidup di hosted.

## 5.9 Stok bahan (inventori)

- **Master bahan:** nama 2–60, satuan dasar **g/ml/pcs terkunci setelah dibuat** (`base_unit_locked` — mengubah satuan akan membuat saldo lama tidak terdefinisi), batas minimum, biaya per satuan (terisi otomatis saat pembelian diterima). Chip **HABIS** / **DI BAWAH MINIMUM**.
- **Ledger mutasi** `stock_movements` **append-only** (trigger menolak UPDATE/DELETE) dengan 5 sumber: `PURCHASE`, `RECIPE`, `PRODUCTION`, `WASTE`, `ADJUSTMENT`; setiap baris menyimpan `balance_after` (saldo = total berjalan material + bukti jejak).
- **Koreksi/Waste:** segmented Koreksi (tanda ±, boleh menambah/mengurangi) vs Waste (selalu negatif, input positif ditolak), alasan wajib ≥3 char, saldo negatif ditolak server (`insufficient_stock`). Pembulatan ke satuan dasar (`inv_to_base`: kg→g ×1000, l→ml ×1000, aliases pcs/butir/dll.).
- **Potong stok otomatis saat bayar** — trigger `AFTER INSERT ON payments` → `inv_post_sale_usage`: kebutuhan per bahan = `Σ(ri.qty × si.qty / rv.yield_qty)` pada resep **aktif** produk `stock_mode='RECIPE'`; pre-check semua bahan (gagal = `insufficient_stock: nama…`, tidak ada tulisan parsial); guard defensif satu set mutasi `RECIPE` per sale (replay checkout tidak memotong dua kali). Produk `BATCH` **tidak** dipotong saat bayar.
- **Riwayat mutasi** per bahan: 50 baris terakhir, panah naik/turun, saldo sesudah, sumber, waktu WIB.
- **Uji:** `inventory_pages_test` + **57 cek integrasi** `test_inventory.py`.

## 5.10 Pembelian

- **Buat pembelian:** supplier opsional, tanggal, status **Terima langsung** / **Pesanan dulu**, baris dinamis (bahan, qty dalam satuan dasar — kg/l diterima & dikonversi, **Total harga per baris** (bukan harga satuan — server membagi sendiri), total berjalan).
- **Server** (`inv_create_purchase`): `unit_cost = round(total_price / qty_base)` (**metode harga terakhir** — bukan rata-rata bergerak), `line_total = round(total_price)`; bila RECEIVED langsung posting mutasi `PURCHASE` + memperbarui `ingredients.unit_cost`.
- **Terima** (untuk ORDERED): dialog konfirmasi → `inv_receive_purchase` — kunci baris, tolak penerimaan ganda (`purchase_already_received`), posting + perbarui `unit_cost`, status RECEIVED + `received_at`.
- Semua lewat retry idempoten (kunci per operasi) — timeout ≠ pembelian ganda.

## 5.11 Resep & HPP — *harga pokok penjualan*

> **Definisi operasional di sistem ini:** HPP = **biaya bahan per porsi** dari
> resep aktif, memakai `unit_cost` terkini (harga pembelian terakhir). Ini
> disebut terus-terusan sebagai **estimasi**, bukan HPP akuntansi penuh.

**Rumus persis (`inv_hpp`, migrasi 0010):**

```text
cost_i          = round(qty_i × unit_cost_i)                    -- per bahan, per batch
hpp_per_portion = round( Σ cost_i / yield_qty , 2)              -- yield = porsi per batch
margin_per_porsi = harga jual − round(hpp_per_portion)
```

**Alur halaman Resep & HPP (master–detail):**

1. Kiri: daftar produk aktif (tanpa terarsip) dengan penanda `stock_mode` — *RECIPE* "dimasak saat dipesan" vs *BATCH* "siap per batch".
2. Kanan: status jujur — **"resep belum ada"** (bukan klaim stok 0 / HPP 0!), versi resep aktif, tabel biaya per bahan (qty × unit_cost + saldo bahan saat ini), **HPP per porsi**, margin per porsi (merah bila negatif), total biaya batch.
3. **Simpan resep baru** → `inv_save_recipe`: versi lama dinonaktifkan, versi baru `max+1` (jejak riwayat HPP), 1–50 item, yield 1–10000, dialog menjelaskan *"kuantitas untuk SATU batch utuh; HPP dibagi yield"* → fungsi mengembalikan `inv_hpp` terbaru.
4. **Riwayat versi** dengan centang versi aktif + waktu WIB.

**Produksi batch (produk BATCH):** dialog "jumlah porsi dihasilkan" →
`inv_produce_batch`: `faktor = qty_produced / yield_qty`, kebutuhan per bahan
`= ri.qty × faktor`, pre-check stok, insert `production_batches`, posting
mutasi `PRODUCTION` (ref `batch:<id>`). *Bahan dipotong di sini; penjualan
tidak memotong lagi.*

**Penting & jujur (temuan teknis laporan ini):**

- `cost_allocate` / biaya operasional **TIDAK** dimasukkan ke `inv_hpp` —
  tidak ada SQL yang mengalikan overhead ke per porsi. HPP = bahan saja.
- `pos_reports.hpp_ingredient_cost` = `Σ(qty terjual × Σ(qty_bahan × unit_cost))`
  pada resep aktif — yaitu **biaya per batch**, **tanpa membagi `yield_qty`** di
  CTE laporan (migrasi 0012 baris 514–526). Saat `yield = 1` hasilnya identik
  dengan `inv_hpp`; saat `yield > 1` laporan **lebih besar** dari HPP per
  porsi × qty. Label UI memang menyebut "estimasi". **Rekomendasi:** samakan
  dengan `/ yield_qty` pada iterasi laporan berikutnya (perubahan SQL + uji
  integrasi dalam satu commit).

## 5.12 Biaya operasional

- **Tabel `expenses`**: 7 jenis (LISTRIK, LPG, AIR, KEMASAN, SEWA, INTERNET, LAINNYA), nominal int, **`kind` = ACTUAL (tagihan nyata) / ESTIMATED (asumsi)** — enum ketat agar estimasi **tidak pernah** menyamar jadi bukti pembayaran; `source_ref` menautkan baris hasil kalkulator energi (`energy_estimate:<id>`), ikon bohlam vs struk di UI.
- **Editor**: jenis, deskripsi ≥3, nominal ≥0, toggle ACTUAL/ESTIMATED dengan penjelasan, URL bukti opsional, tanggal (2020–2100, default hari WIB). Baris dari kalkulator energi bertanda "dari kalkulator".
- **Alokasi biaya** (`cost_allocate`): operator **menyebut nominal** dari satu biaya ke `target_ref` bebas (mis. "batch-gorengan", "meja-3", "1 Nov") — **bukan persentase, bukan per-sale otomatis**. Guard server: `Σ alokasi ≤ nominal biaya` (`allocation_exceeds_source`, divalidasi ulang saat biaya diperkecil); `unique (expense_id, target_ref)` → alokasi ulang target sama = **menimpa**, bukan menambah. Laporan hanya menampilkan total `allocated_total`.
- **Update biaya** (id terisi) sengaja **tanpa** kunci idempotency (idempoten alamiah — nilai yang sama diterapkan ulang); **buat baru** lewat `MutationRetryStore` (mode "Ulangi biaya yang sama" saat timeout).

## 5.13 Kalkulator Energi — **Listrik & LPG**

> Modul `lib/features/energy/energy_page.dart` (479 baris) + fungsi server
> `energy_save_estimate` (migrasi 0012). Desain inti: **klien menampilkan
> pratinjau live; server MENGHITUNG ULANG rumus yang sama dan selalu menulis
> hasil sebagai biaya ESTIMATED** — asumsi tidak pernah berubah diam-diam
> menjadi tagihan.

**Tab 1 — Listrik (kWh):**

| Kolom | Default | Arti |
|---|---|---|
| Daya (W) | 800 | daya alat yang dipakai |
| Durasi (jam) | 3 | lama nyala per sesi |
| Faktor beban (%) | 80 | porsi daya yang benar-benar terpakai (mis. kompor/kulkas tidak full-load) |
| Tarif (Rp/kWh) | 1500 | tarif PLN per kWh |

```text
kWh = round( watt × jam × (faktor_beban / 100) / 1000 , 3 )
biaya_listrik = round( kWh × tarif )                    -- integer Rupiah
biaya_per_porsi = porsi ≤ 0 ? 0 : round(biaya / porsi)
```

Contoh: 800 W × 3 jam × 80% / 1000 = **1,920 kWh** → × Rp1.500 = **Rp2.880**
untuk 10 porsi = **Rp288/porsi**.

**Tab 2 — LPG (3 kg):** pendekatan **pro-rata per jam bakar** (bukan
kcal/kaloritas & efisiensi tungku — disengaja: sederhana & terverifikasi
operator):

| Kolom | Default | Arti |
|---|---|---|
| Harga isi ulang (Rp) | 22.000 | harga tabung 3 kg |
| Jam efektif per tabung (jam) | 20 | berapa lama satu tabung habis |
| Durasi batch (jam) | 2,5 | lama satu kali masak/menggoreng |

```text
biaya_per_jam  = round( harga_isi_ulang / jam_efektif )
biaya_LPG      = round( harga_isi_ulang / jam_efektif × durasi_batch )
biaya_per_porsi= round( biaya_LPG / porsi )
```

Contoh: Rp22.000 / 20 jam = **Rp1.100/jam** → batch 2,5 jam = **Rp2.750**.

**Alur simpan (kedua tab):**

1. Pratinjau tampil hanya bila semua kolom valid (selain itu "Isi semua kolom…").
2. Tombol simpan → `MutationRetryStore.run(operation: 'energy_save_estimate')` — bila ada mutasi tertunda, **seluruh form dikunci** dan tombol berubah jadi **"Ulangi estimasi yang sama"** (payload identik, kunci sama → server tidak menggandakan).
3. Server memvalidasi (porsi > 0; listrik: watt>0, jam>0, 0<beban≤100, tarif≥0; LPG: harga≥0, jam efektif>0, batch≥0), **menghitung ulang rumus**, lalu:
   - insert `expenses` (`type='LISTRIK'|'LPG'`, `kind='ESTIMATED'`, deskripsi "Estimasi listrik 1,92 kWh" / "Estimasi LPG batch 2,5 jam") + `source_ref`,
   - insert `energy_estimates` (semua parameter mentah → bisa diaudit/diuji ulang),
   - tulis `audit_events`, kembalikan `{estimate_id, kind, kwh, cost, portions, expense_id}`.
4. Konfirmasi menampilkan **nilai dari server** + pengingat "ESTIMATED, bukan biaya aktual".
5. Halaman Stok/HPP/laporan tidak terpengaruh langsung — energi masuk lewat **biaya** (jenis LISTRIK/LPG) dan muncul di laporan sebagai `expenses_estimated`/`expenses_by_type`.

**Kasus tepi yang ditangani:** pemisahan meter rumah (petunjuk: isi porsi
bisnis saja), koma vs titik desimal, porsi 0 diblokir, kind pending ≠ tab
aktif → tombol simpan dinonaktifkan (tidak bisa salah jenis saat replay).

**Uji:** `operating_cost_test` (Flutter) + **41 cek integrasi**
`test_operating_cost.py` (termasuk rumus server vs klien, alokasi, kas shift,
laporan).

## 5.14 Kas shift

- **Buka:** hitung uang fisik laci → `cash_shift_open(kas_awal)` (tolak bila sudah ada shift OPEN — indeks parsial unik di DB).
- **Status live:** `expected_cash = opening_cash + Σ(payments.amount − sales.refund_amount)` untuk metode **CASH** sejak shift dibuka (netto refund, floor 0) — *Transfer/QRIS tidak menambah uang tunai fisik* ditegaskan di UI.
- **Tutup:** dialog terisi otomatis `expected` → operator memasukkan hasil hitung fisik + catatan → `cash_shift_close` menghitung ulang expected, `variance = actual − expected` (boleh negatif), audit expected/actual/variance, SnackBar *"Selisih Rp X (harap Rp A, fisik Rp B)"*.
- Kasus tepi: metode non-tunai dikecualikan, refund menurunkan penjualan tunai netto, saldo negatif di-clamp 0, `invalid_actual_cash`/`no_open_shift` ditangani.

## 5.15 Laporan & ekspor CSV

- **Rentang tanggal** (default 7 hari WIB) → `pos_reports(p_from, p_to)` — semua filter memakai tanggal **WIB**; null default = hari ini − 6 hari.
- **Isi laporan** (8 kartu + grafik):
  1. `net_sales = Σ(total − refund_amount)` tanpa baris REFUNDED;
  2. `refunds` = `Σ refund_amount` (semua, termasuk yang sudah REFUNDED);
  3. `transactions` (tanpa REFUNDED);
  4. **Biaya bahan (estimasi)** = HPP resep × qty terjual (lihat catatan yield §5.11);
  5. Biaya aktual periode / estimasi periode (per `expense_date`);
  6. Ter alokasi (total `cost_allocations` sepanjang masa);
  7. **Selisih setelah HPP & biaya aktual\*** = `net_sales − hpp − expenses_actual` (dengan bintang: bukan laba bersih);
  8. Tren omzet harian (bar ternormalisasi, penjaga semua-nol), Menu terlaris (top 10 qty), Biaya per kategori (Aktual/Est per jenis), kartu **"Catatan jujur"** (3 bullet: HPP estimasi resep×harga kini; ESTIMASI ≠ tagihan; angka tanpa tenaga kerja/susut/pajak).
- **Ekspor CSV** (`buildReportCsv`): header `Bagian,Kunci,Nilai`; seksi Periode → Penjualan → Biaya → Tren → Menu terlaris → Biaya per kategori; angka **integer polos tanpa pemisah ribuan** (disengaja untuk diproses ulang); escaping tanda kutip ganda. Web: unduh Blob dengan **BOM UTF-8** (Excel Indonesia); platform lain: share sheet.
- Uji: `operating_cost_test` + `csv_export_stub_test` + 41 cek integrasi.

## 5.16 Pengaturan usaha

- Satu baris `business_settings(id=1)`: nama (2–80), alamat (≤200), zona waktu (harus ada di `pg_timezone_names`), **pajak & biaya layanan** (persen 0–100 di UI → fraksi 0–1 di DB, koma/titik diterima).
- Simpan → `settings_save` (guard operator + validasi server + audit before/after); gagal validasi tidak berdampak data.
- **Seksi Notifikasi pesanan** (lokal perangkat): switch suara (default aktif), pilihan 4 nada + **Pratinjau**, slider volume (default 0.8) — semuanya SharedPreferences perangkat, tidak menyentuh server.
- Catatan jujur di UI: preferensi printer & mode offline tidak tersedia pada MVP ini.

## 5.17 Ketahanan jaringan: Mutation Retry

**Masalah yang diselesaikan:** timeout di jaringan warung — operator tidak tahu apakah transaksi masuk; menekan ulang = risiko dobel.

**Desain (`lib/core/mutation_retry.dart` + migrasi 0013/0014):**

```text
Slot pending = "<uid>:<operasi>:<target>"  →  di SharedPreferences (bukan DB)
1. cek slot; ada dengan parameter BERBEDA → 'pending_mutation_conflict'
   (UI masuk mode "ulangi permintaan yang sama", input dikunci)
2. belum ada → buat kunci idempoten 32 hex (Random.secure) → SIMPAN SLOT DULU
   sebelum kirim (pulih mati listrik)
3. kirim {params + p_idempotency_key}
4. server (mutation_run_once): cek is_operator → validasi kunci 8–128 →
   pg_advisory_xact_lock(op:key) → baris di mutation_requests?
     • request identik  → balas cache + idempotent_replay: true
     • request beda     → 'idempotency_key_conflict'
     • tidak ada         → jalankan *_once, simpan (request, response)
5. sukses → hapus slot. Gagal VALIDASI bisnis (P0001 non-konflik) →
   key terbukti belum pernah commit → hapus slot & lempar ulang.
   Konflik idempoten → slot DIPERTAHANKAN.
```

**Tidak ada replay otomatis saat aplikasi dibuka** — replay terjadi saat
operator membuka form yang sama; tiap form terdampak (`energy`, `expenses`,
`purchases`, `adjust stock`, `refund`, `produce batch`) memuat ulang slot
pending, mengunci input, dan menawarkan tombol **"Ulangi … yang sama"**.
Enam operasi tercakup: `pos_refund`, `inv_adjust_stock`, `inv_create_purchase`,
`inv_produce_batch`, `exp_save` (jalur buat), `energy_save_estimate`.
Checkout POS memakai kunci per percobaan bayar yang di-supply `_PaymentSheet`.
Jaminan jujur yang tercatat di kode: ini **identitas retry**, bukan outbox
saldo — wipe penyimpanan perangkat tetap butuh rekonsiliasi buku besar.

## 5.18 Pencetakan, berbagi, dan format

- **QR meja**: PNG via `RepaintBoundary` (pixelRatio 3) → share sheet OS (pemilih printer/WA ada di OS) — tanpa paket `printing`.
- **Struk**: dialog + share teks/PNG (share sheet).
- **CSV laporan**: Blob+BOM di web, share sheet di platform lain.
- **Format**: `formatRupiah` id-ID (`Rp 15.000`, `-Rp` untuk negatif), `formatWib` dengan nama bulan Indonesia statis (deterministik tanpa `initializeDateFormatting`).


# 6. Implementasi ML — dari fitur sampai model otomatis

> **Arah tunggal yang dipilih** (keputusan D-06, `docs/decision-log.md` +
> `docs/ml-roadmap.md`): **demand forecasting per menu, per jam/hari, dengan
> evaluasi & promosi model otomatis.** Angka keluaran = estimasi jumlah
> terjual, bukan perintah belanja. Bagian ini menjelaskan **implementasi ML
> sistem ini apa adanya** — arsitektur berlapisnya, bagaimana tiap lapisan
> bekerja, rumusnya, dan bagaimana sistemnya menilai diri sendiri.

## 6.1 Arsitektur berlapis (apa yang dibangun)

```text
┌─ Lapisan 4 — Keputusan otomatis (champion/challenger) ──────────────┐
│  cron malam → backtest rolling-origin → banding baseline →          │
│  promosi model menang / rollback kalah / turun kelas saat drift     │
│  → semua keputusan tercatat audit (jejak bisa ditelusuri manusia)   │
├─ Lapisan 3 — Model prediktif ───────────────────────────────────────┤
│  Fase 1: exponential smoothing (Holt-Winters) per menu di SQL —     │
│  parameter diupdate tiap data masuk, tanpa layanan Python           │
│  Fase 2: gradient boosting (LightGBM/CatBoost) — fitur hari/libur   │
│  Fase 3: champion/challenger penuh + drift monitor per menu         │
├─ Lapisan 2 — Baseline deterministik (selalu tersedia) ──────────────┤
│  naive musiman (nilai pekan lalu pada hari/jam sama) + EWMA         │
│  dihitung langsung Postgres — inilah "gerbang numerik": model       │
│  prediktif HANYA sah jika mengalahkan lapisan ini                   │
├─ Lapisan 1 — Fitur & agregat (LIVE, migrasi 0017) ──────────────────┤
│  5 view agregat + index: grain per item/hari/jam/menu/bahan,        │
│  zona Asia/Jakarta eksplisit, refund dikeluarkan dari target        │
└──────────────────────────────────────────────────────────────────────┘
        ↑ seluruh lapisan berjalan di Postgres yang sama; tidak ada
          library ML di Flutter/QR web (klien hanya membaca angka)
```

## 6.2 Lapisan 1 — gudang fitur (terpasang & teruji di repo)

Lima view dari `supabase/migrations/20261030000017_analytics_aggregates.sql`,
semuanya `security_invoker = true` (RLS tabel dasar tetap berlaku), grant
hanya `authenticated`, plus index `sales(created_at)` dan
`sale_items(product_id, sale_id)`:

| View | Grain (1 baris =) | Kolom kunci / rumus | Peran sebagai fitur ML |
|---|---|---|---|
| `v_sale_item_facts` | item terjual | `sale_day = (created_at at tz 'Asia/Jakarta')::date`, `sale_hour`, `day_of_week` (1=Sen…7=Min), `hour_of_day` (0–23), `qty`, `line_revenue = qty × unit_price`, `dining_type`, `sale_status` | **Matriks fitur mentah**: lag & pola musiman dibangun dari sini |
| `v_sales_daily` | hari | `transactions`, `counted_transactions` (tanpa REFUNDED), pisah DINE_IN/TAKEAWAY, `gross_total`, `discount/tax/service_total`, `refund_total`, `net_total = Σ(total − refund_amount)` | Target agregat omzet; uang dihitung **per transaksi** (bukan per item) supaya join item tidak menggandakan omzet |
| `v_sales_hourly` | jam | `sale_hour` (date_trunc jam WIB), `transactions`, `net_total` | **Fitur musiman jam** — jam ramai vs jam sepi |
| `v_product_daily` | menu × hari | `qty`, `revenue`, `transactions` (distinct sale), `where sale_status <> 'REFUNDED'` | **TARGET forecasting** (`y` per menu per hari) |
| `v_stock_usage_daily` | bahan × hari × sumber | `qty_in`, `qty_out`, `movements`, sumber (PURCHASE/RECIPE/PRODUCTION/WASTE) | **Jembatan prediksi → kebutuhan bahan**: forecast qty menu diterjemahkan jadi kebutuhan bahan lewat resep aktif |

**Ketentuan kejujuran data yang memengaruhi model:**

- Hari/jam dihitung `at time zone 'Asia/Jakarta'` (pola perbaikan 0011) — fitur kalender konsisten dengan WIB, bukan zona device.
- `REFUNDED` dikeluarkan dari target menu; **refund sebagian belum dikurangi** di view (nilai pastinya di tabel `refunds`) — tercatat sebagai pekerjaan saat fase berikutnya aktif.
- Nama menu di-snapshot per transaksi → rename menu memisah baris, tidak dipaksa digabung (kejujuran label > kelengkapan).
- Hari libur besar Indonesia masuk sebagai fitur kalender di fase berikutnya (kalender eksternal, bukan data historis).

**Fitur turunan yang dibangun di atas lapisan ini** (spesifikasi pipeline):
`lag-1/7/14/28` (kemarin, pekan lalu, dst.), rata-rata bergerak (EWMA),
indikator hari (Sen–Min), indikator jam, **harga dari
`product_price_history`** (harga berubah → permintaan berubah; history
terisi otomatis oleh trigger setiap operator mengubah harga), jenis sajian
(dine-in vs takeaway), kalender hari besar.

## 6.3 Lapisan 2 — baseline deterministik (mesin "selalu benar")

Dua model sederhana yang **bisa dihitung Postgres murni** dan selalu menjadi
pembanding wajib:

```text
Naive musiman (pekan lalu):
    ŷ(menu, hari, jam) = y(menu, hari − 7, jam)        -- jam/hari sama, pekan lalu
EWMA (exponential weighted moving average):
    ŷ_t = α·y_t + (1 − α)·ŷ_{t−1}                     -- α kecil (mis. 0,2–0,3),
                                                       -- stabil terhadap lonjakan sekali
```

Baseline ini **tidak pernah bisa "gagal"** — ia selalu menghasilkan angka dari
data historis murni. Itulah fungsinya: sistem hanya boleh menampilkan angka
model yang lebih canggih **jika membuktikan diri lebih akurat dari baseline
ini**; jika pipeline model mati, tampilan terdegradasi ke baseline, bukan
kosong-menipu (guardrail #6).

## 6.4 Lapisan 3 — model prediktif per fase

**Fase 1 — exponential smoothing per menu (Holt-Winters), di SQL/pgPL:**

```text
Level : L_t = α·y_t + (1 − α)·(L_{t−1} + T_{t−1})
Trend : T_t = β·(L_t − L_{t−1}) + (1 − β)·T_{t−1}
Ramalan h hari ke depan:  ŷ_{t+h} = L_t + h·T_t
  × faktor musiman hari/jam (rasio rata-rata hari itu terhadap rerata pekan)
Pooling/shrinkage: menu kecil → ditarik ke rerata kategorinya
  (mengatoverfitting pada menu dengan penjualan sedikit)
```

- Parameter diupdate **tiap data masuk**, berjalan di SQL — **nol infrastruktur tambahan** (tanpa layanan Python, tanpa GPU, tanpa antrean).
- Output: **"estimasi kebutuhan bahan besok"** sebagai saran — operator menyetujui; sistem tidak pernah memesan sendiri (guardrail #2, larangan PRD).
- Cocok untuk 0–8 minggu histori: sedikit parameter, tahan data kecil.

**Fase 2 — gradient boosting (LightGBM/CatBoost), training harian otomatis:**

- Dilatih lewat cron (GitHub Actions yang sudah ada / Supabase Edge Function), membaca lapisan 1, menulis prediksi ke tabel.
- Keunggulan model ini untuk kasus ini: fitur **kategori** (hari, jam, hari besar) langsung optimal dipakai; interaksi non-linear (mis. harga naik + akhir pekan) tertangkap otomatis dari `product_price_history`.
- Mulai memakai `v_stock_usage_daily` untuk menerjemahkan forecast menu → kebutuhan bahan (dibagi yield resep, persis rumus `inv_post_sale_usage` yang sudah dipakai pemotongan stok nyata — satu bahasa rumus untuk stok nyata & prediksi).

**Fase 3 — champion/challenger penuh:** monitoring drift per menu, kalender
hari besar Indonesia, dan eksperimen terkontrol (mis. "apakah prediksi
meleset saat harga turun?" — memakai riwayat harga yang sudah otomatis
tercatat).

**Jadwal aktivasi (syarat kuantitatif — angka, bukan tanggal):**

| Fase | Syarat minimal | Gerbang skor untuk lanjut |
|---|---|---|
| 1 — statistik online | ≥ 300 transaksi & ≥ 3 minggu histori | MAPE mingguan < baseline "pekan lalu" |
| 2 — gradient boosting | ≥ 1.500 transaksi, ≥ 8–12 minggu, ≥ 6 hari aktif/minggu | WAPE harian < 30% & kalahkan baseline musiman |
| 3 — auto-evaluation | ≥ 6 bulan stabil termasuk ≥ 2 periode promo/harga berubah | WAPE membaik ≥ 5% vs fase 2 pada rolling 4 pekan |

## 6.5 Lapisan 4 — loop "belajar sendiri & berkembang sendiri"

Inilah yang membuat sistem ini *otomatis*, bukan sekadar prediksi sekali jalan:

```text
cron harian (GitHub Actions / Supabase Edge Function)
  → baca 5 view agregat (fitur + target)
  → bangun fitur: lag-1/7/14/28, rata-rata bergerak, hari, jam,
    harga (product_price_history), jenis sajian, hari besar
  → latih kandidat (challenger)
  → backtest ROLLING-ORIGIN atas 4 pekan terakhir:
        latih 3 pekan → uji 1 pekan → geser → ulangi (4 lipatan)
  → BANDINGKAN dengan baseline (naive musiman + EWMA)
      menang (≥3 dari 4 lipatan) → tulis model sebagai CHAMPION
                                   + prediksi ke tabel  [auto-promote]
      kalah → pertahankan champion / mundur ke baseline
              + CATAT ALASAN di jejak evaluasi
  → setiap prediksi disimpan bertanggal; aktualnya dihitung besok
      → skor kualitas (WAPE) mengalir sendiri ke evaluasi berikutnya
  → DRIFT: error melonjak 2× lipat selama 7 hari
      → turun kelas otomatis ke baseline
      → panel menampilkan "prediksi dinonaktifkan sementara"
```

**Metrik (dipilih agar jujur pada data kecil):**

```text
WAPE = Σ|y − ŷ| / Σy            -- metrik UTAMA: tahan menu volume kecil
MAPE = mean(|y − ŷ| / y)         -- hanya untuk menu dengan ≥ 20 penjualan
                                   (menu jarang = MAPE meledak, dipisah)
```

**Tiga jaminan agar boleh dibiarkan jalan sendiri:**

1. **Gerbang numerik, bukan optimism model** — kandidat hanya naik kelas bila
   mengalahkan baseline pada data yang belum pernah dilihatnya (backtest).
2. **Rollback otomatis** — champion memburuk → mundur ke baseline
   deterministik yang selalu bisa dihitung ulang di Postgres.
3. **Jejak audit** — setiap promosi/rollback/drift tercatat (pola
   `audit_events`), sehingga keputusan otomatis bisa ditelusuri manusia.

## 6.6 Tabel & kontrak sistem prediksi (didesainkan, bernama di roadmap)

| Tabel | Isi |
|---|---|
| `demand_forecasts` | prediksi per menu × hari × jam + versi model + status (aktif/baseline/berhenti) |
| `forecast_actuals` | pasangan prediksi × aktual → WAPE berjalan (skor mengalir otomatis) |
| `ml_eval_runs` | hasil backtest tiap malam: model, skor, keputusan promosi/rollback |
| `ml_model_registry` | artefak model, hyperparameter, rentang data, checksum |

## 6.7 Guardrail (mengikat, bukan saran)

1. **Amendemen PRD §9 lebih dulu** untuk kode model fase 2+ — dokumen keputusan mengikat proses; lapisan agregat/baseline sudah berada di koridor "agregat deterministik" yang diizinkan MVP.
2. **Tidak pernah memesan sendiri** — prediksi hanya menyusun *saran kebutuhan bahan*; tombol persetujuan tetap di tangan operator (larangan pembelian otomatis PRD).
3. **Label jujur** — setiap angka prediksi ditandai "estimasi, bukan jaminan"; saat sistem gagal → status nonaktif, bukan angka lama.
4. **Tanpa ML di klien** — tidak ada library ML di Flutter/QR web; klien hanya membaca angka hasil server.
5. **Privasi** — hanya agregat menu/jam; tanpa identitas pelanggan (PRD §10). Nama/WA dari wizard hanya untuk penagihan.
6. **Determinisme saat gagal** — pipeline cron mati → tampilan terdegradasi ke baseline musiman yang bisa dihitung Postgres, bukan kosong-menipu.
7. **Audit setiap keputusan otomatis** — promosi/rollback/drift selalu tercatat.

## 6.8 Uji kelayakan (protokol pertama kali syarat fase terpenuhi)

1. Ambil 4 pekan terakhir → rolling-origin (latih 3, uji 1, geser, ulangi).
2. Bandingkan tiga kandidat: (a) naive musiman, (b) EWMA/Holt-Winters, (c) gradient boosting.
3. Metrik: WAPE utama; MAPE per menu hanya untuk menu ≥ 20 penjualan.
4. Lolos gerbang hanya bila (b) atau (c) **konsisten** mengalahkan (a) di ≥ 3 dari 4 lipatan. Kalau tidak: **tidak diluncurkan**, alasan dicatat di roadmap, ulangi tiga bulan kemudian.

## 6.9 Posisi implementasi saat ini (1 Nov 2026)

- **Lapisan 1 (gudang fitur): LIVE di hosted** — 5 view terpasang, tercatat di `schema_migrations` (0017), teruji `test_analytics_views.py` (8 pemeriksaan, job CI `migrations`) termasuk indeks, grain, zona WIB, dan pengecualian refund.
- **Lapisan 2 (baseline): tersedia by construction** — kedua baseline bisa dihitung dari view yang sudah ada; menjadi kontrak pembanding untuk selamanya.
- **Lapisan 3–4 (model & auto-evaluation):** desain lengkap, rumus, gerbang kuantitatif, kontrak tabel, dan guardrail terdokumentasi di `docs/ml-roadmap.md` (keputusan D-06) — dijadwalkan oleh **syarat data**, bukan tanggal, mengikuti amendemen PRD §9.
- **Volume data terkini** (dicek langsung 1 Nov 2026): 12 transaksi, 2 hari aktif (data uji di-reset setelah Sprint 06/07); syarat fase 1 (≥300 transaksi, ≥3 minggu) menjadi tonggak pertama yang harus dicapai operasional nyata — hingga itu, yang tampil adalah dashboard deskriptif + (saat fase 1 aktif) baseline musiman yang selalu benar.

## 6.10 Kandidat turunan dari data baru Sprint 07 (tercatat untuk fase lanjut)

Fitur kerja Sprint 07 membuka dua sinyal baru yang terkumpul **otomatis** tanpa upaya operator:

1. **Estimasi waktu masak/ETA pesanan QR** — `audit_events` mencatat `CLAIM`/`PREPARE` dan `qr_drafts` menyimpan `created_at → COMPLETED`; durasi per jam bisa di-median dulu (statistik murni), ML hanya bila jitter besar. Berguna untuk jujur ke pelanggan ("±15 menit").
2. **Draft OPEN_BILL yang tidak jadi bayar (no-show)** — dari `pay_intent` + pelunasan `sale_id`; **ditunda** sampai ada volume draft nyata dan keputusan privasi terkait (PRD §10).

Keduanya **bukan** pengganti arah utama (demand forecasting) — didaftarkan sebagai kandidat sekunder agar keputusan masa depan tidak hilang.


# 7. Pengujian, CI/CD, dan operasi

## 7.1 Peta test (angka terverifikasi 1 Nov 2026)

| Lapisan | Jumlah | Lokasi | Cara jalankan |
|---|---|---|---|
| Unit/widget Flutter | **195 test, 0 analyze** | `apps/pos_flutter/test/` (21 file: app 4, core 4, features 13) | `flutter analyze && flutter test` |
| vitest web QR | **21** | `apps/qr_web/test/app.test.js` | `npm test` |
| E2E Playwright | **6** | `tests/e2e/qr_customer.spec.js` (semua RPC di-mock `page.route`) | `npm test` (tests/e2e) |
| Integrasi → **database hosted** | **245 PASS, 0 FAIL** | `tests/integration/test_pos_api.py` (77), `test_inventory.py` (57), `test_operating_cost.py` (41), `test_qr_drafts.py` (70) | `OPERATOR_PASSWORD=… python3 <file>` |
| Integrasi → Postgres polos CI | 3 suite: `test_mutation_retry` (19), `test_settings_edit` (4), `test_analytics_views` (8) | butuh `DATABASE_URL` (CREATE DATABASE) — dijalankan job `migrations` | CI otomatis |

**Cakupan test integrasi utama** (245 cek hosted): uang (kuotasi, diskon,
pajak, layanan, kembalian, replay idempoten, refund ganda/berlebih), stok
(potong resep saat bayar, batch, koreksi/waste, penerimaan ganda, saldo
negatif), operasional (rumus energi server vs klien, alokasi melebihi biaya,
kas shift, laporan), QR (submit anon, rate limit, idempotency per meja,
preferensi/identitas, **siklus hidup penuh 0019**: CLAIMED→PREPARING→COMPLETED,
pelunasan, papan aktif, cancel dari PREPARING).

## 7.2 CI/CD (`.github/workflows/`)

**`ci.yml`** — push `main` + semua PR, **4 job paralel**:

1. `flutter` — `flutter analyze` + `flutter test` (cache SDK).
2. `qr-web` — Node 22: `npm ci` → `npm run build` → `npm test`.
3. `e2e` — Playwright chromium (install `--with-deps`), webServer Vite di
   port 5199, upload trace saat gagal (retensi 7 hari).
4. `migrations` — service `postgres:15` polos → `apply_migrations.sh`
   (semua 19 migrasi harus idempoten di Postgres tanpa Supabase) → 3 suite
   Python integrasi.

**`deploy-qr-web.yml`** — push `main` yang menyentuh `apps/qr_web/**`:
`npm ci` → test → `vite build --base=/SmartPOS/` dengan `VITE_SUPABASE_URL`
& `VITE_SUPABASE_PUBLISHABLE_KEY` dari **repo variables** (hanya key
publishable; tidak ada rahasia) → `actions/deploy-pages` → live di
**https://awaaaaja.github.io/SmartPOS/**. URL ini dipakai Flutter via
`--dart-define=QR_WEB_URL` untuk membentuk tautan QR `<URL>/?token=…`.

Riwayat terakhir: CI run #11+ **success**, Deploy Pages run #2+ **success**.

## 7.3 Operasi database & backup

- **Migrasi diterapkan bertahap ke hosted** dengan `psql -f` + pencatatan
  manual ke `supabase_migrations.schema_migrations` (kata sandi hanya lewat
  env var, tidak pernah di URL/perintah/log).
- **Backup** sebelum migrasi berisiko: dump skema/data ke
  `/tmp/opencode/smart-pos-backups/` (mode 0700/0600, di luar Git);
  catatan prosedur lengkap di `docs/backup-restore.md`.
- **Kredensial**: `Kredensial.md` + `.env.local` = lokal saja, masuk
  `.gitignore`; `Kredensial.md` tidak pernah ter-commit (diperiksa pada
  setiap commit).

## 7.4 Konvensi pengembangan yang diterapkan konsisten

- **Satu commit = satu fase lengkap termasuk migrasi + test integrasi
  pendampingnya** (aturan repo; mis. Fase C `b119dc0` = migrasi 0019 +
  19 cek integrasi baru + UI Flutter + 20 test baru dalam satu commit).
- Gate sebelum commit: `flutter analyze` **0 issue** + suite penuh lulus.
- Dokumen ikut diperbarui tiap fase: `docs/plan-qr-wizard-notif.md` (tabel
  status), `docs/api-contracts.md` (kontrak RPC), `docs/sprint-log.md`
  (bukti per bagian), `PRD.md` (catatan perubahan bila lingkup menyentuh
  PRD), `docs/decision-log.md` (keputusan).
- Test harness Flutter: tanpa jaringan — fake repository (`extends
  QrDraftRepository` + `SupabaseClient` dummy), `InMemorySharedPreferencesAsync`
  untuk prefs async, seam global (`notifSoundPlayer`, `waLaunchHandler`,
  `sharePngHandler`) untuk hal yang hanya bisa diverifikasi di device.

# 8. Peta dokumen Markdown repository

## 8.1 Dokumen utama (root)

| File | Peran |
|---|---|
| `README.md` | Peta struktur repo + cara menjalankan (Supabase, Flutter, web, test) |
| **`PRD.md` (v2.1)** | Spesifikasi produk: lingkup satu operator (§2.2), 13 destinasi, FR (POS SCR-02, FR-07 tanpa halaman pesanan), **§9 "Dashboard Aktif, Bukan Machine Learning"**, §10 privasi, UAT-01… (UAT-02 = draft QR muncul di panel/tab pesanan), kriteria rilis §13, catatan perubahan (termasuk catatan 1 Nov 2026: tab Pesanan = evolusi panel QR Masuk) |
| `Sprints.md` (v2.1) | Backlog per tiket (S02…S06) file-per-file + acceptance criteria |
| `Prompt.md` | Aturan build untuk coding agent (brand, foto legal/berlisensi, tanpa ML di klien, dsb.) |
| `Kredensial.md` | **Lokal saja (gitignored)** — kredensial operasional |

## 8.2 `docs/` — keputusan, kontrak, dan laporan

| File | Peran | Status |
|---|---|---|
| `docs/plan-qr-wizard-notif.md` | **Plan eksekusi v4** (E seed, Fase 1–3, §A3, B, C, D) + tabel status eksekusi | **Seluruh bagian SELESAI** (1 Nov 2026) |
| `docs/api-contracts.md` | Kontrak API per endpoint: `pos_*`, `inv_*`, `qr_*`, `exp_*`, `cash_*`, `settings_save` + preferensi 0018, **siklus hidup pesanan 0019** (papan aktif, `qr_mark_preparing`, 4 cabang `qr_complete_draft`), arsip katalog (Fase D), notifikasi Fase B (lokal perangkat), view agregat 0017 | Aktif, diperbarui tiap fase |
| `docs/sprint-log.md` | **Sprint 06** (polishing/QA/keamanan, PARTIAL/RELEASE BLOCKED jujur) + **Sprint 07** (plan v4: semua bagian + bukti test) | Aktif |
| `docs/ml-roadmap.md` | **Roadmap ML post-MVP** (D-06): arah, 5 view, syarat fase, loop champion/challenger, guardrail, uji kelayakan, risiko | Keputusan terikat |
| `docs/decision-log.md` | D-01…D-06+: keputusan arsitektur (WIB/D-04, ML/D-06, tanpa role, dsb.) | Referensi |
| `docs/backup-restore.md` | Prosedur dump/restore privat (25 tabel, checksum) + verifikasi | Referensi operasional |
| `docs/handover.md` | Serah-terima pengetahuan proyek | Referensi |
| `docs/ui-diff.md` | Diff visual antar-build | Referensi |
| `docs/release-notes.md` | Catatan rilis | Referensi |
| `docs/evidence/sprint06/README.md` | Bukti-bukti Sprint 06 (audit layar, UAT, keamanan) | Arsip |
| **`docs/laporan-konkrit-smart-pos.md`** | **Laporan konkrit ini** — seluruh repo, fitur + alur, HPP & energi, implementasi ML | 1 Nov 2026 |

## 8.3 Dokumen pendukung lain

- `docs/ml-roadmap.md` §"Referensi" menunjuk `PRD.md` §9,
  `decision-log` D-06/D-04, `api-contracts` bagian view agregat, migrasi
  0017, dan `test_analytics_views.py` — sirkulasi rujukan yang sudah rapi.
- `supabase/migrations/*.sql` — 19 file, tiap file berheader komentar tujuan
  (dokumentasi teknis tersendiri).
- `supabase/seed/seed_dev.sql` — fixture **[DEMO]** untuk pengembangan lokal.
- `.github/workflows/*.yml` — dokumentasi pipeline hidup.

# 9. Status, temuan, dan rekomendasi lanjutan

## 9.1 Status eksekutif

| Dimensi | Status |
|---|---|
| Rencana `plan-qr-wizard-notif.md` v4 | **100% selesai** (E, Fase 1–3, A, A3, B, C, D) — semua ter-commit, live, teruji |
| Kualitas Flutter | 195/195 test, analyze 0 |
| Kualitas backend | 245 cek integrasi hosted PASS + 3 suite CI, 19 migrasi tercatat & live |
| Kualitas web | vitest 21/21, e2e 6/6, live di GitHub Pages |
| CI/CD | 4 job hijau; Deploy Pages sukses |
| ML | Lapisan fitur (5 view) live & teruji; baseline by construction; model per fase + loop auto-evaluation terdesain lengkap dengan gerbang angka (D-06) |
| Kepatuhan | Uang integer & server-authoritative; tanpa secret di repo/klien; foto legal; larangan PRD (role, halaman pesanan, otomasi belanja, ML klien) dipatuhi |

## 9.2 Temuan teknis dari pemeriksaan laporan ini

1. **Yield tidak dibagi di HPP laporan** — `pos_reports.hpp_ingredient_cost`
   memakai biaya *per batch* tanpa `/ yield_qty`, padahal `inv_hpp` memang
   membagi yield. Dampak: untuk resep yield > 1, biaya bahan di laporan &
   kartu dashboard melebih-tinggi (menyedihkan margin). UI sudah melabeli
   "estimasi", tapi numerik sebaiknya disamakan. **Perbaikan:** `round(sum(...) / rv.yield_qty, 2)` di CTE `hpp_cost` + sesuaikan test integrasi `test_operating_cost.py` dalam satu commit.
2. **`cost_allocate` tidak masuk HPP** — alokasi biaya hanya mengendap di
   `allocated_total` laporan. Bila Waroeng MeJeng butuh "HPP penuh"
   (bahan + energi/overhead), rutenya sudah tersedia: alokasi per
   `target_ref` → tinggal fungsi agregasi baru; namun keputusan harus
   eksplisit agar tidak mengubah arti angka lama secara diam-diam.
3. **Volume data operasional nyata sangat kecil** (12 transaksi, 2 hari
   aktif per 1 Nov 2026 — tampaknya reset pasca-uji). Gerbang fase 1 ML
   (≥300 transaksi, ≥3 minggu) baru tercapai setelah operasional berjalan
   penuh; hingga itu jawaban yang benar tetap dashboard deskriptif +
   baseline — bukan angka model pura-pura.
4. **Refund sebagian belum dikurangi di `v_product_daily`** — sudah tercatat
   di roadmap sebagai pekerjaan fase lanjut (nilai pastinya ada di tabel
   `refunds`).
5. **`/tmp` tooling psql hilang antar-sesi** (binaries ekstrak tidak
   persisten) — untuk sesi berikutnya cukup pakai REST (operasi baca) atau
   re-ekstrak; ketiga suite `DATABASE_URL` memang dirancang untuk CI.

## 9.3 Rekomendasi lanjutan (berurutan nilai/risiko)

1. **Perbaiki pembagian yield di `hpp_cost`** (temuan #1) — kecil, berdampak
   langsung ke kejujuran angka laporan; migrasi + test integrasi satu commit.
2. **Baseline musiman non-ML di laporan** (naive pekan lalu / EWMA dari view
   0017) — manfaat nyata pertama bagi operator ("pekan lalu hari ini laku X
   porsi") sekaligus menjadi pembanding wajib fondasi ML.
3. **Kembalikan data nyata** — jalankan operasional beberapa minggu; syarat
   fase 1 di `ml-roadmap.md` §3 adalah penentu "kapan".
4. **ETA pesanan QR** (median durasi CLAIM→COMPLETED per jam, statistik
   murni) — sinyal sudah otomatis terkumpul sejak Fase C; didaftarkan ke
   roadmap sebagai kandidat sekunder.
5. Bila amendemen PRD §9 dibuka → eksekusi fase 1 ML persis sesuai
   `ml-roadmap.md` (Holt-Winters di SQL, gerbang MAPE vs baseline).

---

*Laporan disusun dari pemeriksaan langsung codebase (19 migrasi, 21 file test
Flutter, seluruh `lib/features`, `apps/qr_web`, workflows CI) dan verifikasi
data live via REST operator, 1 November 2026.*



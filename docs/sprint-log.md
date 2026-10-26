# Sprint Log

## Sprint 01 — Laporan Implementasi
Tanggal: 26 Oktober 2026
Target/tiket: S01-01 … S01-08
Status: **PARTIAL** (S01-01 & S01-08 menunggu perangkat Android & remote Git; sisanya DONE dengan bukti)

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
| Unit/widget Flutter | `flutter test` | **PASS** | 19/19 lulus (formatters, error mapper, theme, shell tablet/HP, login) |
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

### Acceptance Criteria
- [x] `npm run dev`/`build` jalan dengan `.env.example` (QR web).
- [x] Brand `#930031`, Material Icons, tanpa emoji, tanpa halaman AI.
- [x] 1 identitas operator; tanpa role switch.
- [x] Publik vs operator terpisah (uji REST nyata di atas).
- [x] Shell tablet + HP teruji widget test; tanpa Dapur/Pesanan/Pegawai.
- [ ] `flutter run` di perangkat Android: **belum** — tidak ada
  device/emulator di lingkungan ini (build APK debug berhasil, instal manual).
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

### Sisa pekerjaan
- TODO: jalankan `flutter run` pada tablet/HP target; screenshot bukti.
- TODO: push repository ke GitHub agar CI berjalan nyata.
- BLOCKED: S01-01 gate "Build Android debug di device" menunggu perangkat.
- Tiket pertama berikutnya: **S02-01** (CRUD kategori/menu/harga di Flutter).

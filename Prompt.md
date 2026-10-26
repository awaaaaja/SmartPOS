# Prompt.md
## Instruksi Pembangunan Produk Smart POS F&B — Waroeng MeJeng Kampoeng

| Atribut | Ketentuan |
|---|---|
| Versi | **1.0 (MVP single-operator, tanpa ML)** |
| Acuan produk | `PRD.md` **v2.1** |
| Rencana kerja | `Sprints.md` **v2.1**, **Sprint 01–06 saja** |
| Referensi visual/interaksi | `index.html` (prototipe interaktif, **bukan** kode produksi) |
| Aplikasi utama | **Flutter Android**, tablet landscape prioritas, responsif untuk HP |
| Halaman pelanggan | **Vue.js**, web responsive dari QR meja, tanpa login pelanggan |
| Penyimpanan | Supabase Auth, PostgreSQL, Storage dan Realtime jika diperlukan |
| Sumber kebenaran transaksi | Backend/API terproteksi dan transaksi PostgreSQL atomik |
| Operator | **1 orang** yang menangani seluruh aktivitas usaha |
| Warna brand primer | **`#930031`** |
| Ikon | **Flutter Material Icons** (`Icons.*`), bukan emoji |
| ML/AI | **DILARANG pada MVP**; tidak ada model, inference API, forecast, atau halaman AI |
| Status awal | Rencana pengembangan; **jangan menganggap sprint sudah selesai** |

> Dokumen ini berisi instruksi **siap pakai untuk coding agent**. Tempatkan `Prompt.md`, `PRD.md`, `Sprints.md`, dan `index.html` di root repository sebelum memulai. Agent harus mengerjakan fitur nyata, bukan hanya membuat screenshot, landing page, data dummy permanen, atau mockup statis.

---

# 1. Urutan Sumber Kebenaran

Gunakan urutan prioritas berikut jika dokumen atau prototipe tidak sama:

1. **Keputusan ruang lingkup terakhir** dalam dokumen ini: satu usaha, satu operator, tidak ada Dapur/Pesanan terpisah, **MVP tanpa ML**, warna `#930031`, tanpa emoji.
2. `PRD.md` v2.1: aturan bisnis, alur transaksi, data, UAT, kebijakan HPP/biaya dan keamanan.
3. `Sprints.md` v2.1: urutan tiket, dependensi, deliverable, acceptance criteria dan gates.
4. `index.html`: **referensi komposisi layar, perilaku, flow, grouping konten dan microinteraction**.
5. Keputusan teknis yang dicatat di `docs/decision-log.md` setelah diuji dan disetujui.

**Konflik yang diketahui pada mockup lama:** `index.html` mungkin masih memiliki warna hijau, emoji makanan/ikon, kartu AI Insights, atau angka simulasi. **Jangan salin bagian-bagian itu** ke aplikasi Flutter. **Ganti brand dengan `#930031`, gunakan Material Icons dan foto menu yang legal, hilangkan AI**, gunakan data asli dari backend setelah implementasi.

Jangan mengubah alur bisnis untuk mengejar kemiripan pixel-perfect bila hal tersebut membuat kalkulasi salah atau kebocoran keamanan. Catat penyimpangannya di `docs/ui-diff.md` dan jelaskan alasan teknis.

---

# 2. MASTER PROMPT — SALIN KE CODING AGENT

```text
Kamu adalah senior Flutter engineer, backend/PostgreSQL engineer, UI engineer,
dan QA engineer untuk proyek Smart POS Waroeng MeJeng Kampoeng.

BACA TERLEBIH DAHULU, tanpa melewati urutan:
1. Prompt.md ini, termasuk seluruh aturan UI dan larangan.
2. PRD.md v2.1 sebagai spesifikasi perilaku bisnis.
3. Sprints.md v2.1 sebagai backlog implementasi.
4. index.html sebagai referensi tampilan, struktur halaman, dan interaksi.
5. README, package manifest, migration, source code dan test yang sudah ada.

PRODUK YANG HARUS DIBANGUN:
- Satu aplikasi Flutter Android untuk satu operator/kasir Waroeng MeJeng Kampoeng.
- Tablet Android landscape adalah layout utama; HP portrait tetap berfungsi.
- Web Vue untuk pelanggan scan QR meja, pilih makanan/minuman, dan mengirim
  draft keranjang ke panel QR Masuk di layar Kasir POS.
- Satu operator menyelesaikan semua transaksi dan administrasi sendiri.
- Tidak ada akun staf, role switch, halaman Pesanan terpisah, layar Dapur,
  status kitchen, multi-cabang, multi-tenant, subscription, atau fitur SaaS.
- Tidak ada ML/AI di MVP. Jangan membangun atau memalsukan forecasting,
  model, data hasil prediksi, pipeline training, ml_api, atau halaman AI Insights.
- Warna utama brand HARUS #930031. UI dilarang memakai emoji dan tampilan
  generik AI; gunakan Flutter Material Icons (Icons.*) yang didukung secara
  native, tipografi jelas dan foto menu legal yang dikonfigurasi owner.

KERJAKAN DENGAN METODE READ → THINK → BUILD → REVIEW → FIX:
READ   : audit file, cek status tiket dan dependensi, lihat implementasi ada.
THINK  : tulis rencana perubahan berkas, data flow, edge case, dan tes.
BUILD  : implementasi fitur sebenarnya dari tiket, bukan placeholder.
REVIEW : jalankan format/lint, unit/widget/integration tests, uji API/DB/UI.
FIX    : perbaiki error dan regression sampai acceptance criteria lulus.

ATURAN EKSEKUSI:
1. Kerjakan SATU sprint yang aktif sesuai Sprints.md, berurutan dari tiket
   awal yang belum DONE. Jangan lompat ke ML atau memperluas scope.
2. Jangan menimpa implementasi yang sudah benar. Baca dan reuse komponen.
3. Setiap tombol/menu harus punya aksi nyata atau status disabled yang jujur.
4. Jangan gunakan data dummy sebagai data transaksi produksi. Fixture hanya
   di development/staging dan diberi penanda DEMO.
5. Jangan menggunakan localStorage browser sebagai database produksi.
6. Perhitungan uang, harga, HPP dan stok harus benar, deterministik,
   teruji, dan divalidasi oleh backend.
7. Jangan simpan service-role key atau secret server pada Flutter/web.
8. Setiap pembayaran dan mutasi stok harus tahan retry serta tercatat audit.
9. Jika konfigurasi Supabase, kredensial, atau perangkat fisik belum tersedia,
   siapkan .env.example, adapter dan instruksi setup, lalu lanjutkan
   pekerjaan yang tidak terblokir. Jangan mengaku integrasi telah berhasil.
10. Catat hasil nyata ke docs/sprint-log.md. Checklist menjadi DONE hanya
    jika build dan test terkait benar-benar lulus.

SETIAP SELESAI TIKET ATAU SEKELOMPOK TIKET, LAPORKAN:
- Tiket dan tujuan pengguna.
- File yang dibuat/diubah.
- Perubahan skema/API dan alasan.
- Alur UI yang sekarang benar-benar bisa dijalankan.
- Perintah tes yang dijalankan beserta PASS/FAIL sesungguhnya.
- Bukti hasil (screenshot/device log) bila tersedia.
- Bug, risiko, blocker, dan langkah perbaikan berikutnya.
- Status tiket yang diperbarui di Sprints.md.

MULAI dari memeriksa repository dan Sprint 01, kecuali sudah ada tiket DONE
berdasarkan bukti test. Jangan membuat kesimpulan 'selesai' dari mockup HTML.
```

---

# 3. Kontrak Desain Flutter: Tidak Generic AI, Tidak Emoji

## 3.1 Identitas visual dan token

Gunakan **Material 3** dengan warna yang konsisten. Token berikut adalah default awal (nilai pelengkap boleh disesuaikan bila uji kontras memerlukannya, primary tetap harus `#930031`).

| Token | Hex | Tujuan |
|---|---|---|
| `brandPrimary` | `#930031` | Tombol utama, navigasi aktif, penekanan identitas |
| `brandDark` | `#660023` | Pressed state, bagian header berkontras |
| `brandSoft` | `#FBEAF0` | Selected pill, highlight/filter aktif |
| `canvas` | `#FCF8FA` | Latar aplikasi |
| `surface` | `#FFFFFF` | Card, form, sheet |
| `textPrimary` | `#21161C` | Teks utama |
| `textSecondary` | `#6E6268` | Metadata dan helper |
| `border` | `#E9DCE2` | Divider/batas input |
| `success` | `#187449` | Sukses/tersimpan (bukan brand) |
| `warning` | `#B96D14` | Peringatan stok dan konflik harga |
| `error` | `#B42318` | Error dan pembatalan |

Contoh seed tema **harus diadaptasikan ke arsitektur repo**, jangan tempel seluruh komponen ke satu file:

```dart
const brandPrimary = Color(0xFF930031);

final theme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: brandPrimary,
    brightness: Brightness.light,
  ).copyWith(
    primary: brandPrimary,
    onPrimary: Colors.white,
    surface: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF21161C),
  ),
  scaffoldBackgroundColor: const Color(0xFFFCF8FA),
);
```

**Jangan** membuat kartu dengan gradient mencolok, glassmorphism berlebihan, ilustrasi robot, ikon sparkles di seluruh tempat, teks acak, lorem ipsum sebagai konten produk, atau UI dashboard generik yang tidak mencerminkan operasional warung. Fokus pada kepadatan informasi yang tepat, hierarki visual jelas, dan kasir yang cepat dioperasikan.

## 3.2 Ikon open-source yang didukung Flutter

Gunakan Material Icons bawaan Flutter tanpa package ikon tambahan bila tidak perlu. Ikon boleh memakai varian `*_rounded` jika tersedia di SDK yang digunakan. Gunakan `Icon` atau `IconButton` dengan label/tooltip yang sesuai.

| Navigasi/aksi | Material Icon Flutter yang direkomendasikan |
|---|---|
| Dashboard | `Icons.dashboard_rounded` |
| Kasir POS | `Icons.point_of_sale_rounded` |
| QR Meja | `Icons.qr_code_2_rounded` |
| Menu & Harga | `Icons.restaurant_menu_rounded` |
| Promo | `Icons.local_offer_rounded` |
| Stok bahan | `Icons.inventory_2_rounded` |
| Resep & HPP | `Icons.menu_book_rounded` |
| Pembelian | `Icons.shopping_basket_rounded` |
| Biaya Operasional | `Icons.account_balance_wallet_rounded` |
| Listrik / Energi | `Icons.bolt_rounded` |
| LPG | `Icons.local_fire_department_rounded` |
| Air | `Icons.water_drop_rounded` |
| Kas Shift | `Icons.payments_rounded` |
| Riwayat | `Icons.receipt_long_rounded` |
| Laporan | `Icons.bar_chart_rounded` |
| Pengaturan | `Icons.settings_rounded` |
| Tambah/hapus/ubah | `Icons.add`, `Icons.delete_outline`, `Icons.edit_outlined` |
| Sukses/peringatan/error | `Icons.check_circle_outline`, `Icons.warning_amber_rounded`, `Icons.error_outline` |

**Dilarang**: emoji sebagai ikon makanan, tombol, empty state, splash, ilustrasi atau logo; karakter Unicode seperti `⌂`, `▣`, `✦` sebagai pengganti ikon; font emoji; ikon tiruan dari teks. Foto menu menggunakan asset asli atau placeholder visual **netral** `Icons.restaurant_rounded` sampai owner mengunggah foto. Jangan mengunduh foto sembarang dan mengklaim foto itu sebagai menu Waroeng MeJeng.

## 3.3 Layout dan navigasi yang meniru perilaku `index.html`

**Tablet landscape (prioritas):**

- Sidebar navigasi stabil (lebarnya konsisten), header menampilkan nama usaha dan koneksi.
- Layar Kasir POS: **katalog menu dan pencarian di area utama; keranjang + ringkasan harga di samping**. Panel `QR Masuk` tampil di bagian atas/di dalam POS, bukan halaman baru.
- Grid makanan/minuman foto, nama, harga dan status habis. Gunakan fixed aspect ratio dan teks dengan ellipsis bila perlu.
- CTA Bayar mudah ditemukan, ukuran nyaman disentuh, disable jika cart kosong atau checkout sedang diproses.
- Modal pembayaran dapat berupa `Dialog`/`BottomSheet` adaptif. Setelah bayar, tampilkan hasil, struk, dan aksi kembali ke kasir.

**HP portrait:**

- Bottom navigation: **Beranda, Kasir, Stok, Laporan, Lainnya**.
- Halaman POS menampilkan kategori/menu; keranjang dapat membuka persistent bottom sheet atau route sheet di dalam konteks POS, tanpa mengubahnya menjadi halaman Pesanan.
- `QR Masuk` menggunakan badge jumlah draft dan panel yang bisa diperluas. Tidak bergantung pada hover.
- Form panjang memiliki scroll yang benar, elemen aksi tetap dapat diakses dengan keyboard tampil.
- Tidak boleh ada `RenderFlex overflow`, nested scrolling yang membuat form macet, atau sidebar yang bertabrakan dengan topbar.

**Perilaku interaktif wajib:**

| Layar | Interaksi yang harus benar-benar berfungsi |
|---|---|
| Beranda | KPI dari DB, filter tanggal jika ada, shortcut yang membuka tujuan nyata |
| POS | Cari/filter menu, add item, varian/topping, qty +/- , hapus, ubah meja, diskon, quote, bayar, struk |
| QR Masuk (di POS) | Badge, refresh, detail draft, ambil ke keranjang, konflik keranjang/harga, cancel draft berizin |
| Menu & Harga | Tambah/edit/arsip, foto, harga baru, variant/modifier, status tersedia |
| Meja & QR | Tambah meja, lihat tautan, generate QR aktual, rotasi, salin/share tautan |
| Stok | Pencarian, tambah bahan, koreksi beralasan, mutasi, stok minimum |
| Resep & HPP | Pilih menu, tambah bahan/takaran, yield dan unit, hitung HPP, simpan versi |
| Pembelian | Input pembelian dan penerimaan, update ledger, tampilan riwayat |
| Energi | Edit watt, durasi, load factor, tarif, LPG, porsi; hasil recalculated langsung; simpan estimasi |
| Biaya | Input aktual/estimasi, daftar histori, rincian alokasi tanpa double count |
| Kas Shift | Buka kas, hitung expected cash, input kas fisik, selisih, tutup shift |
| Riwayat | Filter/search, lihat struk snapshot, refund dengan alasan |
| Laporan | Grafik **historis**, filter periode, export CSV bila masuk sprint, empty state jujur |
| Pengaturan | Profil, tarif, biaya layanan, opsi perangkat, logout |
| Web QR | Buka menu, cari/filter, tambah menu, modifier, keranjang, kirim draft, konfirmasi nomor referensi |

## 3.4 Animasi yang layak untuk produk

Animasi **harus memberi feedback interaksi** dan jangan memperlambat transaksi:

- `AnimatedSwitcher` untuk badge QR masuk, total keranjang, dan state sukses.
- `AnimatedContainer` untuk kategori/filter terpilih dan card expandable.
- `Hero` bila membuka detail menu dengan foto asli dan navigasi membutuhkannya.
- Feedback sentuh/ink response sesuai Material, loading indicator selama API, success state sesudah server confirm.
- Durasi pendek dan konsisten. Hormati pengaturan pengurangan animasi sistem jika tersedia.
- Jangan membuat animasi looping dekoratif, shimmer tak selesai, atau toast sukses sebelum server mengonfirmasi.

## 3.5 Standar responsivitas dan UX

- Minimal target sentuh sekitar **48 dp** untuk aksi penting, dapat dijangkau dengan jari.
- Tipografi jelas (Rupiah dan angka tabular bila memungkinkan), kontras cukup, error tepat di field.
- Gunakan `SafeArea`, `LayoutBuilder`/breakpoints, `MediaQuery`, dan kontrol scroll yang tepat; jangan hardcode ukuran tablet tertentu.
- State `initial/loading/empty/data/error/offline` dirancang per modul. Empty state menampilkan ajakan tindakan yang relevan, tanpa emoji.
- Pada Android tablet 10–11 inci, POS harus bisa dioperasikan cepat tanpa pindah halaman untuk transaksi.
- Jangan mengubah navigasi produk hanya karena HTML prototipe menggunakan pendekatan DOM yang berbeda dengan Flutter.

---

# 4. Kontrak Arsitektur dan Kualitas

## 4.1 Struktur minimum repository

```text
waroeng-mejeng-pos/
├── Prompt.md
├── PRD.md
├── Sprints.md
├── index.html                     # referensi desain, bukan kode app Flutter
├── README.md
├── apps/
│   ├── pos_flutter/
│   │   ├── lib/
│   │   │   ├── app/               # router, theme, adaptive shell
│   │   │   ├── core/              # network, error, formatters, shared widgets
│   │   │   └── features/
│   │   │       ├── auth/
│   │   │       ├── dashboard/
│   │   │       ├── pos/           # TERMASUK QR Masuk & pembayaran
│   │   │       ├── catalog/
│   │   │       ├── tables_qr/
│   │   │       ├── inventory/
│   │   │       ├── recipes_hpp/
│   │   │       ├── purchases/
│   │   │       ├── expenses/
│   │   │       ├── energy/
│   │   │       ├── cash_shift/
│   │   │       ├── sales_history/
│   │   │       ├── reports/
│   │   │       └── settings/
│   │   └── test/
│   └── qr_web/                    # Vue responsive pelanggan
├── services/
│   └── business_api/              # backend bisnis, satu implementasi authoritative
├── supabase/
│   ├── migrations/
│   └── seed/                     # fixture dev/staging terpisah
├── tests/
│   ├── integration/
│   └── e2e/
└── docs/
    ├── decision-log.md
    ├── api-contracts.md
    ├── ui-diff.md
    ├── sprint-log.md
    ├── test-results.md
    └── release-notes.md
```

**Direktori/fitur yang dilarang untuk MVP:** `ml_api/`, `ai_insights/`, `forecasting/`, `kitchen/`, `orders_page/`, `staff_roles/`, `tenants/`, `branches/`, `subscriptions/`.

## 4.2 Backend dan transaksi

- Gunakan Supabase Auth satu akun operator, konfigurasi sesi aman, RLS/API authorization.
- Pelanggan QR hanya boleh membaca menu publik dan membuat draft terproteksi rate limit; tidak bisa membaca sale, pembayaran, resep, biaya, atau kontak pribadi.
- API publik menggunakan token meja yang sulit ditebak dan dapat dirotasi. Jangan mengekspos secret operator.
- Satu bisnis = satu record konfigurasi; tidak memodelkan sistem SaaS.
- Gunakan **integer Rupiah** dan decimal terkontrol untuk berat/volume.
- Quote dan checkout dihitung di server; frontend hanya mengirim ID item/varian, kuantitas, diskon yang diizinkan, dan pilihan metode pembayaran.
- Checkout memerlukan idempotency key dengan unique constraint server dan transaksi database atomik agar tidak menghasilkan double sale/payment/stok.
- Ketika transaksi final disimpan, item menyimpan snapshot harga, modifier, qty dan identitas menu. Perubahan katalog tidak mengubah sale lama.
- Draft QR tidak termasuk omzet, pembayaran, maupun pengurangan bahan. Pada claim, cek ulang aktif/harga dan tampilkan konflik.
- Refund dicatat di ledger, bukan menghapus sale lama. Lakukan rekonsiliasi nilai refund terhadap net sales dan kas.
- Pemakaian bahan dapat berasal dari sale final **atau** produksi batch yang direkam, sesuai resep; tidak boleh dikurangi dua kali. Menu tanpa resep menampilkan status belum terhitung, bukan stok fiktif.
- Bedakan biaya aktual dan estimasi. Satu sumber expense tidak boleh dialokasikan lebih dari sekali.
- Jangan menyatakan QRIS/transfer otomatis terverifikasi kecuali benar-benar ada integrasi PSP dengan konfirmasi sah. Untuk MVP, pembayaran non-tunai diverifikasi **manual operator**.
- Simpan timestamp UTC di DB bila sesuai stack; format untuk operator `Asia/Jakarta`, tanggal dan Rupiah `id-ID`.

## 4.3 Kalkulator energi dan HPP

```text
kWh = (watt × durasi_jam × faktor_beban) / 1000
biaya_listrik = kWh × tarif_Rp_per_kWh
biaya_LPG_batch = (harga_isi_ulang / jam_efektif_tabung) × jam_batch
biaya_per_porsi = biaya_langsung_batch / jumlah_porsi_valid
HPP_bahan = Σ(jumlah_bahan_dalam_satuan_dasar × harga_per_satuan_dasar)
margin_kontribusi = harga_bersih - biaya_variabel_langsung
```

- Tampilkan satuan dan asumsi; jika meter listrik gabung rumah, jangan menganggap seluruh tagihan adalah biaya usaha.
- Hitung biaya kulkas/alat variable-load dengan faktor beban atau data pengukuran, bukan otomatis memakai daya puncak sepanjang hari.
- Jangan menyebut estimasi hasil operasional sebagai **laba bersih** jika komponen belum lengkap.

## 4.4 Testing minimum

| Lapisan | Yang wajib diperiksa |
|---|---|
| Flutter unit | Uang, rounding, perhitungan tampilan quote, input validator, format WIB/Rupiah |
| Flutter widget | Layout tablet/HP, menu/filter, cart/modifier, QR panel, sheet bayar, input biaya |
| Vue unit/component | Menu, keranjang, pilihan varian, QR token invalid, retry submit |
| Database/API | RLS, token, idempotency, harga dari server, sale/payment/stok atomik, refund |
| End-to-end | POS manual → bayar → histori; web QR → POS QR Masuk → checkout; stok → HPP; biaya → laporan |
| Perangkat Android | Landscape tablet, portrait HP, keyboard, overflow, network loss, orientation |
| Security | QR publik menolak akses internal; tidak ada kunci rahasia dalam build |
| Regression | Harga diubah setelah sale, checkout double tap, stock rollback, alokasi listrik tidak dobel |

Tes harus menggunakan nilai yang diketahui dan ekspektasi yang dihitung independen, bukan sekadar snapshot UI yang selalu lulus.

---

# 5. PROMPT PER SPRINT — EKSEKUSI BERURUTAN

## Sprint 01 — Fondasi Flutter, design system, database, login

```text
Lanjutkan pembangunan MVP Waroeng MeJeng, Sprint 01 sesuai Sprints.md
(S01-01 sampai S01-08). Baca PRD.md dan index.html dahulu.

Target implementasi:
- Buat monorepo Flutter Android, Vue QR, Supabase migrations dan core API.
- Terapkan Material 3 brand #930031 + warna pendamping dari Prompt.md.
- Seluruh ikon UI memakai Flutter Icons.*; tanpa emoji; tanpa halaman AI.
- Bangun responsive shell: tablet sidebar, mobile bottom navigation.
- Buat halaman UI asli untuk navigasi yang akan diisi berikutnya;
  jangan tampilkan angka/fitur seolah sudah terkoneksi jika belum.
- Integrasikan login satu operator; setup DB/constraint/RLS dan client.
- Siapkan environment example, README, automated lint/test/CI.

Buktikan flutter analyze, flutter test, build/run Flutter, npm build
(serta tes DB bila lingkungan tersedia). Laporkan tiket DONE berdasarkan
bukti. Jangan membuat fitur Dapur/Pesanan atau ML.
```

## Sprint 02 — Katalog, harga, Kasir POS, checkout

```text
Kerjakan Sprint 02 (S02-01 sampai S02-10), tetapi hanya setelah gate
Sprint 01 lulus. Implementasikan CRUD menu, kategori, foto, varian,
topping, available state, price history, dan layar Kasir POS sesuai
hierarki/interaksi index.html dengan warna #930031.

POS tablet harus menampilkan katalog + keranjang bersamaan. HP memakai
layout adaptif dan keranjang sheet. Satu tombol Bayar membuka sheet,
quote berasal dari backend, metode tunai/transfer-QRIS manual,
kembalian dihitung valid. Implementasikan transaksi sale/payment,
snapshot harga, audit, idempotency dan riwayat+struk.

Bukti: buat menu, ubah harga, tambah 2 makanan/minuman, pilih topping,
bayar, lihat histori dan struk. Uji double tap, perubahan harga lama,
refund dan rounding. Jangan membuat halaman Pesanan/Dapur/AI.
```

## Sprint 03 — QR pelanggan masuk ke POS

```text
Kerjakan Sprint 03 (S03-01 sampai S03-09). Buat pengaturan meja dan
QR URL HTTPS aktual. Web Vue responsive menyediakan menu publik,
varian, keranjang, submit draft dan konfirmasi referensi.

Saat pelanggan submit, aplikasi Flutter Kasir POS menampilkan badge
'QR Masuk' dan draft di dalam layar POS itu sendiri. Operator dapat
melihat, mengambil ke keranjang, mengatasi konflik harga/cart, lalu
membayar menggunakan checkout Sprint 02. Jangan buat OrdersPage,
KitchenDisplay, pelacakan status dapur, atau menganggap draft terbayar.

Tes: 2 HP submit bersamaan → dua draft terpisah → operator mengambil
satu draft → checkout → sale final muncul sekali, draft tidak
memengaruhi omzet sampai dibayar. Uji invalid token, retry, rate
limit, refresh/reconnect, serta akses publik yang tidak sah.
```

## Sprint 04 — Inventory, pembelian, resep/HPP

```text
Kerjakan Sprint 04 (S04-01 sampai S04-09). Implementasikan master bahan,
satuan dasar (g/ml/pcs), stok awal, ledger mutasi, pembelian/penerimaan,
resep versi + yield, HPP bahan, batas minimum dan waste.

Transaksi final mem-posting pemakaian resep tepat sekali untuk produk
make-to-order; produk pre-made per batch memakai pencatatan batch agar
stok bahan tidak berkurang ganda. Tampilkan status resep belum ada.

Tes: pembelian menambah bahan, resep menghitung HPP per porsi, sale
mengurangi bahan sekali, retry tidak menggandakan mutasi, refund/waste
mengikuti kebijakan audit. Tidak ada AI recommendation.
```

## Sprint 05 — Listrik, LPG, biaya, kas, laporan

```text
Kerjakan Sprint 05 (S05-01 sampai S05-09). Implementasikan kalkulator
energi interaktif (watt, jam, faktor beban, tarif, jumlah porsi), LPG,
catatan air, sewa, internet, kemasan, biaya aktual vs estimasi,
alokasi tanpa double count, Kas Shift, laporan penjualan/biaya aktual.

Laporan berisi statistik deskriptif saja, BUKAN forecast. Tidak ada
halaman AI Insights. Perbarui UI dengan warna #930031, ikon Material,
grafik historis yang benar-benar membaca backend.

Tes numerik listrik, LPG, biaya/porsi, HPP, rekonsiliasi kas tunai,
refund dan saldo. Tampilkan biaya estimasi secara jujur, jangan klaim
laba bersih jika overhead belum lengkap.
```

## Sprint 06 — Polishing, QA, keamanan, build produk

```text
Kerjakan Sprint 06 (S06-01 sampai S06-10) sebagai sprint penyelesaian
produk MVP, bukan menambah fitur.

Audit setiap layar terhadap PRD dan struktur/interaksi index.html:
brand #930031, Material Icons tanpa emoji, layout tablet landscape,
HP portrait, loading/empty/error, animasi feedback, navigasi dan tombol
benar-benar berfungsi. Tidak ada screens Pesanan, Dapur, Pegawai,
Multi-Branch, Subscription, AI atau ML.

Lakukan regression: kasir manual, QR → POS, harga berubah, refund,
mutasi stok, biaya energi dan laporan, keamanan token, retry, serta
restore backup. Optimalkan performa berdasar pengukuran. Bangun APK
release (dan AAB jika diperlukan) dengan signing yang aman.

Output wajib: file build bila berhasil, changelog, panduan instalasi,
setup Supabase, hasil test, bukti layar real device/emulator, daftar
fitur/limitasi, known issues, dan status gate UAT. Jika tes/build gagal,
jangan menyatakan aplikasi siap produksi.
```

---

# 6. PROMPT TAMBAHAN UNTUK AUDIT/REVIEW

## 6.1 Audit UI dibanding mockup `index.html`

```text
Bandingkan tiap layar Flutter dengan navigasi, grouping konten, dan
perilaku index.html. Buat matriks: halaman referensi → Flutter route →
state nyata → interaksi yang berfungsi → deviasi yang perlu diperbaiki.

Pengecualian wajib: ubah warna utama menjadi #930031, hapus semua emoji,
pakai Material Icons, jangan tampilkan AI Insights. Jalankan widget
screenshots pada HP dan tablet landscape. Temukan overflow, blank state,
broken button, navigation collisions, text clipping, modal yang tidak
bisa ditutup, dan ketidakkonsistenan kontras. Perbaiki berdasarkan
prioritas dampak pada transaksi. Catat hasil dan bukti.
```

## 6.2 Audit transaksi dan stok

```text
Audit semua jalur mengubah uang dan persediaan pada produk MVP. Periksa
server authority untuk harga dan modifier, integer Rupiah, diskon/pajak,
quote, idempotency, uniqueness, atomic transaction, refund ledger,
snapshot historis, mutasi stok dan pembelian yang tidak double-post.

Buat test kasus konkurensi/retry/timeouts dengan expected output
independen. Jika ada mismatch, perbaiki akar masalah. Tidak boleh
menganggap redirect sukses = transaksi database berhasil.
```

## 6.3 Perbaikan bug tanpa merusak modul lain

```text
Baca error/log dan reproduksi bug dahulu. Identifikasi file, state,
API, DB constraint, dan test yang terkait. Buat test yang gagal untuk
mereproduksi bila memungkinkan. Perbaiki bagian terkecil yang cukup,
lalu ulang unit/widget/integration test, audit regresi QR→POS→bayar,
dan catat before/after. Jangan rewrite seluruh aplikasi, menambah
fitur baru, atau mengubah PRD untuk menyembunyikan bug.
```

## 6.4 Audit kesiapan rilis MVP

```text
Nilai status rilis sesuai checklist Sprint 06 dan UAT di PRD.md.
Verifikasi artefak APK, environment/secrets, migrasi, backup/restore,
privasi QR, pembulatan uang, stok/HPP dan alokasi energi. Tuliskan
Pass/Fail/Blocked beserta bukti dan risiko. Jangan menyatakan 'siap'
jika ada P0 gagal atau integrasi yang masih simulasi.

Tidak meminta, melatih, ataupun mengaktifkan model AI/ML pada MVP.
```

---

# 7. Format Progres Wajib Coding Agent

Gunakan template ini setelah menjalankan pekerjaan nyata:

```md
## Sprint 0X — Laporan Implementasi
Tanggal:
Target/tiket:
Status: DONE / PARTIAL / BLOCKED

### Yang dibangun
- [ ] Fitur spesifik + file yang berubah

### Verifikasi
| Pengujian | Perintah/langkah | Hasil | Bukti |
|---|---|---|---|
| Analyze/lint | ... | PASS/FAIL | ... |
| Unit/widget | ... | PASS/FAIL | ... |
| API/DB/integration | ... | PASS/FAIL | ... |
| E2E Android/QR | ... | PASS/FAIL | ... |

### Acceptance Criteria
- [ ] ...

### Temuan dan perbaikan
- Masalah:
- Penyebab:
- Perbaikan:
- Regression check:

### Sisa pekerjaan
- TODO:
- BLOCKED dan ketergantungan:
- Tiket pertama berikutnya:
```

**Larangan pelaporan:** tidak boleh menulis `flutter test PASS`, aplikasi diuji di tablet, Supabase terkoneksi, APK dibangun, atau pembayaran berhasil jika perintah/tes tersebut belum benar-benar dijalankan.

---

# 8. Checklist Akhir Product MVP

- [ ] Aplikasi **Flutter Android** bisa dijalankan dan dipasang, bukan hanya `index.html`.
- [ ] Desain selaras dengan hierarki/alur `index.html`, **brand `#930031`**, tanpa emoji, hanya Material Icons/foto legal.
- [ ] Satu operator dan satu outlet; tidak ada role/kitchen/orders page/SaaS.
- [ ] Menu, harga, varian, topping, status habis, transaksi POS dan pembayaran bekerja.
- [ ] QR pelanggan berfungsi dengan tautan aktual; draft muncul di panel POS, bukan sale otomatis.
- [ ] Auto calculate, snapshot harga, refund, kas shift dan riwayat dapat diaudit.
- [ ] Stok, pembelian, resep/HPP terhubung sesuai aturan, tanpa pengurangan ganda.
- [ ] Listrik, LPG, air, overhead, alokasi biaya tidak dihitung dua kali.
- [ ] Dashboard dan laporan hanya membaca histori aktual, tidak menampilkan prediksi palsu.
- [ ] RLS/API, retry, idempotency, backup/restore dan UAT kritis lulus.
- [ ] Navigasi dan tombol tidak mati; error, loading, empty, offline dikomunikasikan.
- [ ] **Tidak ada model ML, training, API inference, halaman AI, atau dependensi ML** dalam MVP.
- [ ] Sprint 01–06 yang selesai memiliki bukti build/test, bukan sekadar checkbox.

**Definition of shipped MVP:** kasir dapat menjalankan transaksi dari Flutter di tablet, pelanggan dapat mengirim draft dari QR, operator dapat menyelesaikan pembayaran, stok/biaya/laporan tersimpan dengan benar, dan hasilnya dapat dipulihkan serta diaudit. Itu adalah produk MVP, meski belum memiliki Machine Learning.

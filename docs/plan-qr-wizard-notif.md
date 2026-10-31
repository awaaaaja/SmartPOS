# Rencana Lengkap: Wizard Web QR + Pesanan Masuk + Notifikasi Suara + Arsip + Seed Menu

Status: **RENCANA v2 — menunggu persetujuan sebelum eksekusi.**
Tanggal: 31 Oktober 2026. Sumber: bacaan penuh codebase + keputusan diskusi
(mode langkah 1, preferensi bayar ikut ke server, banner+suara in-app,
halaman Pesanan Masuk dengan status Diterima–Diproses–Diselesaikan,
opsi keluarkan dari arsip, seed menu 75 varian).

## 0. Fakta codebase (hasil baca — dasar setiap keputusan)

### Web (`apps/qr_web/`)
- `src/App.vue` (366 baris) satu halaman tanpa langkah; tanpa filter kategori;
  tanpa metode bayar. Submit `qr_submit_draft(token, client_key, items)`,
  idempoten via `localStorage qr_client_key`.
- Test: vitest `test/app.test.js` + Playwright `tests/e2e/qr_customer.spec.js`
  — teks kunci (`Kirim pesanan ke kasir`, `Referensi Q00099`,
  `Pesanan belum dibayar`, `Pesan lagi`, `QR tidak valid`) wajib dipertahankan
  atau disesuaikan sinkron.

### Server (Supabase)
- Siklus draft kini: `PENDING → CLAIMED → COMPLETED/CANCELLED`, PENDING
  kadaluarsa → `EXPIRED` (lazy 2 jam). CHECK constraint
  `('PENDING','CLAIMED','EXPIRED','CANCELLED','COMPLETED')` — **belum ada
  PREPARING**.
- `qr_list_drafts()` **hanya** mengembalikan `PENDING`; `qr_draft_json` belum
  memuat preferensi bayar; `qr_submit_draft` 3 param (belum pernah diubah
  sejak 0008).
- `qr_complete_draft` hanya `CLAIMED → COMPLETED`; `qr_cancel_draft` hanya
  `PENDING|CLAIMED`. Grant: anon = submit+menu saja; sisanya authenticated.
- RLS: `operator_all` untuk `authenticated` pada `products`,
  `product_categories`, `modifiers` dsb. → **update kolom `archived_at`
  langsung dari klien aman tanpa migrasi** (pola `archiveProduct` kini begitu).
- `get_public_menu` menyaring `p.is_active and p.archived_at is null` +
  `c.archived_at is null` → un-arsip otomatis mengembalikan item ke menu web.

### POS Flutter (`apps/pos_flutter/`)
- Panel "QR Masuk" = bottom sheet `QrInboxSheet` dari `PosPage`; polling
  10 dtk & `_claimedDraftIds` (Set lokal di `_PosPageState`) — **claim dan
  penyelesaian terkunci di halaman POS**; `QrDraft` belum punya
  payIntent/payMethod.
- `cartControllerProvider` (Notifier global di `pos_repository.dart`) sudah
  lintas-halaman → dasar kuat memindah klaim ke halaman baru.
- `AppDestination` (13 destinasi, grup Utama/Produk/Keuangan); komentar
  destinations.dart & PRD §2.2 menyebut "tanpa halaman Pesanan" → halaman
  baru = **perluasan panel QR Masuk**, PRD/UAT-02 perlu catatan penyelarasan.
- Katalog: `archiveProduct`/`archiveCategory` + `_confirmArchive` ada;
  **tidak ada `restore` dan tidak ada tampilan daftar arsip** (produk arsip
  hilang begitu saja dari list karena `productsProvider` memakai
  `includeArchived: false`).
- `pubspec.yaml` belum ada dependency audio. Test suite kini **164**.
- Settings hanya `business_settings` dari server — belum ada preferensi lokal.

## A. Wizard Web (3 langkah + konfirmasi)

### A1. Alur & layar
```
[1 MULAI]      Dua kartu: "Bayar sekarang (ke kasir)" (DEFAULT)
               vs "Open Bill" (pesan dulu, bayar nanti).
[2 PILIH MENU] Chip kategori sticky (Semua | Ayam | Mie | Teh | …) →
               grid terfilter; sheet varian/catatan tetap;
               bar bawah "n item · Rp x — Lanjut" + akses keranjang.
[3 PEMBAYARAN] Ringkasan item; PAY_NOW → kartu CASH / QRIS / Transfer;
               OPEN_BILL → "Bayar nanti di kasir";
               tombol "Kirim pesanan ke kasir" (teks dipertahankan).
[KONFIRMASI]   Kartu lama tetap (+ baris metode untuk PAY_NOW);
               "Pesan lagi" → langkah 1, client_key baru.
```
Indikator langkah + Kembali; keranjang bertahan bolak-balik; token tolak →
layar error lama. Tanpa router (ramah GitHub Pages base `/SmartPOS/`).

### A2. Migrasi `20261031000018_qr_payment_pref.sql`
1. `qr_drafts`: kolom `pay_intent` (`PAY_NOW|OPEN_BILL`, null) +
   `pay_method` (`CASH|QRIS|TRANSFER`, null) + CHECK.
2. `qr_submit_draft` → 5 param, 2 baru **default null** (klien & tes lama
   tetap jalan); validasi: method wajib null kecuali PAY_NOW.
3. `qr_draft_json`: sertakan `pay_intent`, `pay_method`.
4. Grant ulang ke signature baru (anon + authenticated).
5. Test integrasi: kasus lama utuh + baru (submit berpreferensi, nilai
   ditolak). Deploy hosted: dump `-Fc` backup → `supabase db push`.

### A3. Dampak POS & test web
- Kartu draft menampilkan preferensi (`PAY_NOW · QRIS` / `Open Bill`) —
  kasir tetap menekan konfirmasi bayar sendiri.
- vitest/e2e disesuaikan bersamaan (wizard + filter kategori + metode);
  teks kunci dipertahankan.

## B. Notifikasi masuk + suara

### B1. `QrInboxWatcher` di `lib/app/shell.dart`
- Polling 10 dtk pindah dari `PosPage` ke shell → berlaku dari halaman
  mana pun, satu sumber `qrDraftsProvider`.
- `ref.listen`: id draft **PENDING baru** → banner in-app
  "Pesanan baru dari Meja 3 · Q00042" (ketuk → navigasi ke **Pesanan
  Masuk**, §C) + mainkan nada bila aktif. Muat pertama = baseline (sunyi);
  deteksi in-memori; restart = baseline baru; draft CLAIMED/COMPLETED tidak
  memicu apa pun.

### B2. Sound & pengaturan
- Aset **Kenney "Notification Sounds" (CC0)** 3–5 `.ogg` di
  `apps/pos_flutter/assets/sounds/` + `README.md` sumber & lisensi.
- Dependency `audioplayers`; lapisan `NotifSound.play(id, volume)` dipancang
  di test (pola `shareSheetHandler`).
- Seksi **"Notifikasi pesanan"** di Settings (lokal, SharedPreferences):
  switch suara (default aktif), pilihan nada + **Pratinjau**, slider volume.
- ~5 test baru (bunyi+banner, baseline sunyi, off = sunyi, preferensi
  tersimpan, pratinjau).

## C. Halaman "Pesanan Masuk" — Diterima → Diproses → Diselesaikan

### C1. Model status & RPC — migrasi `20261031000019_qr_order_lifecycle.sql`
- CHECK constraint: tambah **`PREPARING`** (drop/recreate).
- **`qr_mark_preparing(p_draft_id)`** (baru): atomik
  `CLAIMED → PREPARING`; audit event `PREPARE`; grant authenticated.
- `qr_complete_draft`: terima `CLAIMED` **atau** `PREPARING` → COMPLETED.
- `qr_cancel_draft`: terima `PENDING|CLAIMED|PREPARING`.
- `qr_list_drafts()`: kembalikan **semua status aktif**
  (`PENDING, CLAIMED, PREPARING`) lengkap dengan `status` + `pay_intent`/
  `pay_method` (dari 0018), urut `created_at`. (EXPIRED lazy tetap.)
- Test integrasi: transisi tiap panah, penolakan panah salah, list
  multi-status; **semua kasus lama wajib lulus utuh**.

### C2. UI POS
- `AppDestination.ordersInbox('Pesanan Masuk', Icons.inbox_rounded, grup
  Utama)`; halaman baru `lib/features/orders/orders_inbox_page.dart`:
  - Kartu draft dikelompokkan per status dengan lencana warna:
    `PENDING` **[Diterima]** (= klaim, item masuk keranjang) ·
    `CLAIMED` **[Diproses]** · `PREPARING` **[Selesaikan]** (menuju
    checkout → `qr_complete_draft`) — plus **[Batalkan]** dan
    preferensi bayar dari web (§A3).
  - Konflik harga & item tak tersedia tetap lewat dialog persetujuan
    operator (dipindah utuh dari `PosPage._claimDraft`).
- Ekstraksi: logika klaim → `QrClaimService` (atau fungsi service bersama);
  `_claimedDraftIds` → provider global `claimedDraftIdsProvider` (Notifier)
  supaya `_completeClaimedDrafts` jalan dari halaman mana pun.
- Tombol "QR Masuk" di POS → navigasi ke halaman Pesanan Masuk (badge
  `_QrBadge` tetap, kini di watcher); `QrInboxSheet` dipensiunkan (dihapus)
  — test `qr_inbox_sheet_test.dart` diganti test halaman baru.
- Navigasi dari banner: `selectedDestinationProvider` (Notifier destinasi
  di shell) — NavigationBar HP otomatis menyorot "Lainnya" (sudah ditangani
  kode `idx >= 0 ? idx : length`).

### C3. Penyelarasan dokumen
PRD §2.2 ("tanpa halaman Pesanan") & UAT-02 ("panel QR Masuk, tidak di
halaman pesanan") — halaman ini adalah **evolusi panel QR Masuk** (satu
operator, tanpa dapur/pegawai): catat sebagai perubahan UX di
`docs/api-contracts.md` + PRD changelog, bukan diam-diam.

### C4. Test Flutter
- `orders_inbox_page_test.dart` (pengganti qr_inbox_sheet_test): daftar per
  status, aksi tiap panah, konflik harga, error mapping, empty state.
- `shell_test`/`page_layout_test`: destinasi baru tampil; watcher tidak
  membunuh state halaman.
- Lintas-halaman: klaim dari Pesanan Masuk → checkout di POS → draft
  COMPLETED (claimedDraftIdsProvider).

## D. Keluarkan dari arsip (produk & kategori)

- **Repository** (`catalog_repository.dart`):
  `restoreProduct(id)` / `restoreCategory(id)` →
  `update({'archived_at': null})` — RLS sudah mengizinkan, **tanpa migrasi**.
- **Halaman katalog**:
  - Chip filter di header: **Aktif | Arsip** (state lokal).
  - Produk arsip: chip "Diarsipkan" (sudah ada) + aksi
    **"Keluarkan dari arsip"** (ikon `unarchive`) — ganti/"tambah" tombol
    Arsipkan untuk item terarsip.
  - Sheet kategori: daftar juga menampilkan kategori arsip (abu-abu) dengan
    ikon un-archive; arsipkan tetap tersedia.
- **Provider**: `productsProvider`/`categoriesProvider` → dukung
  `includeArchived` (family) untuk halaman katalog; **POS & menu web tetap
  hanya menampilkan yang aktif** (filter server `get_public_menu` aman).
- **Test** (~4 baru): un-arsip memanggil repo + refresh; item arsip hanya
  tampil di filter Arsip; kategori kembali ke pilihan produk; POS tak
  menampilkan produk arsip.

## E. Seed menu (75 varian = 72 menu + 3 add-on)

- File baru **`supabase/seed/seed_menu_waroeng.sql`** — data NYATA (tanpa
  label `[DEMO]`), idempoten (`where not exists`), dijalankan via SQL editor
  hosted; `seed_dev.sql` tetap utuh untuk dev.
- **17 kategori** mengikuti grup Anda:
  Ayam dan Lauk · Mie · Nasi · Seblak · Camilan dan Sambal · Add-ons Makanan ·
  Teh dan Lemon Tea · Nutrisari dan Minuman Lainnya · Bontea · Chocolatos ·
  Milo · Cappuccino · Beng-Beng · Kopi dan Good Day · Kopi Panas ·
  Beng-Beng Panas · Cappuccino Panas.
- **72 menu** sesuai daftar (harga Rp3.000–Rp18.000 persis sesuai daftar).
- **Item dua harga** — Mie Nasi Goreng (13/18rb) & Nasi Goreng (10/15rb):
  produk dasar harga reguler + **modifier "Ukuran"** (min 1, max 1):
  `Reguler +Rp0`, `Besar +Rp5.000` — mendukung varian di web & POS tanpa
  menggandakan produk.
- **3 add-on** (Tahu, Tempe, Ketimun): masuk kategori "Add-ons Makanan"
  sebagai produk — **harga menunggu keputusan Anda** (lihat pertanyaan).
- Verifikasi: `get_public_menu` menampilkan seluruh kategori/menu; wizard web
  menampilkan filter kategori penuh.

## Fase eksekusi

| # | Fase | Keluaran | Verifikasi |
|---|---|---|---|
| 1 | Migrasi 0018 (preferensi bayar) + test integrasi → hosted | kontrak bayar | PG 5433 hijau; REST 200 |
| 2 | Migrasi 0019 (lifecycle status) + test integrasi → hosted | PREPARING + mark_preparing + list luas | PG 5433 hijau |
| 3 | Wizard web + filter kategori + vitest/e2e | deploy Pages otomatis | CI qr-web + e2e hijau |
| 4 | Halaman Pesanan Masuk + ekstraksi klaim + banner navigasi | alur Diterima–Diproses–Diselesaikan | test Flutter |
| 5 | Sound CC0 + audioplayers + seksi pengaturan | suara & preferensi | test Flutter |
| 6 | Un-arsip produk & kategori + tampilan Arsip | arsip pulih | test Flutter |
| 7 | Seed menu → hosted; analyze 0 + full test + release build → H13Pro | uji E2E nyata | HP pesan → tablet berbunyi → alur status |
| 8 | Docs (api-contracts, PRD catatan, release-notes, sprint-log, handover) + push | rilis tercatat | CI 4 job hijau |

## Risiko & mitigasi

- **Test web putus** → perubahan alur/teks hanya bersamaan dengan
  penyesuaian vitest+e2e pada commit yang sama.
- **Klien lama** → 0018 param default null; drop-create fungsi satu migrasi;
  kasus integrasi lama dipertahankan utuh.
- **List draft melebar** (0019) → badge QR tetap menghitung **PENDING saja**
  (pesan baru ≠ antrean aktif); halaman menampilkan semua status aktif.
- **Suara mengganggu** → default aktif tapi mati/bisa diganti; hanya draft
  BARU yang membunyikan.
- **Seed menimpa data** → file terpisah dari seed_dev, idempoten, jalankan
  manual; dump backup sebelum push migrasi.
- **Arsip tak sengaja** → un-arsip tersedia kembali; tak ada data terhapus
  (arsip = timestamp, bukan hard delete).

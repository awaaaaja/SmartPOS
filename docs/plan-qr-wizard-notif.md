# Rencana Lengkap: Wizard Web QR + Tab Pesanan + Notifikasi Suara + Arsip

Status: **RENCANA v4 — EKSEKUSI berjalan (Fase 1 & 3 selesai 1 Nov 2026).**
Tanggal: 31 Oktober 2026.
Perubahan v4 (atas v3):
1. **Identitas pelanggan di web**: form Nama + No. WA (**opsional**) ikut
   ke server; tampil di kartu pesanan.
2. **Tindak lanjut pembayaran dari tab Pesanan**: tombol **[Bayar]**
   (siapkan keranjang → pindah ke Kasir POS) + tombol **[Hubungi WA]**
   (wa.me prabayar) untuk menagih pesanan belum bayar.
3. **Open Bill = adjustable**: keranjang POS adalah "tagihan berjalan" —
   edit qty, hapus, **tambah item**, diskon, semua bebas sampai dibayar;
   total final = total keranjang saat checkout (bukan snapshot draft).

## Status eksekusi

| Bagian | Status |
|---|---|
| E. Seed menu (2 kategori, 75 varian) | **SELESAI** — commit `84d6afe`+`7e58a85`, live hosted & H13Pro |
| Fase 1. Migrasi 0018 ke hosted + test | **SELESAI** (1 Nov 2026) — commit `2c95897`; hosted `test_qr_drafts.py` **51 PASS, 0 FAIL**; versi 0018 tercatat di `schema_migrations`. Dump cadangan `pre-0018-business.dump`+`pre-0018-auth-users.dump` di `/tmp/opencode/smart-pos-backups/` (0700/0600, tidak masuk Git). Catatan: kolom/fungsi 0018 sudah ada di hosted dari penerapan parsial sebelumnya (tanpa catatan versi) — kini badan fungsi diverifikasi identik dengan file migrasi dan riwayat dilengkapi. |
| A. Wizard web (3 langkah + nama/WA + filter kategori) | **SELESAI** (1 Nov 2026) — vitest 21/21, e2e 6/6, build produksi lulus; foto produk ikut tampil di kartu menu. Menunggu deploy Pages otomatis dari CI. |
| B. Notifikasi banner + suara | Rencana |
| C. Tab Pesanan (v4: bayar & WA dari tab) | Rencana |
| D. Un-arsip katalog | Rencana |

## 0. Fakta codebase (dasar setiap keputusan)

### Web (`apps/qr_web/`)
- `src/App.vue` satu halaman **wizard 3 langkah** (Fase 3 selesai): langkah 1
  niat bayar (Bayar sekarang DEFAULT / Open Bill) + identitas opsional
  (Nama ≤ 60 char; No. WA 8–20 digit, karakter `0-9 + - spasi`); langkah 2
  pilih menu dengan chip kategori sticky (Semua | Makanan | Minuman) + foto
  produk; langkah 3 ringkasan + kartu metode (CASH/QRIS/Transfer) untuk
  PAY_NOW atau "Bayar nanti di kasir" untuk OPEN_BILL. Submit
  `qr_submit_draft(token, client_key, items, intent, method, name, phone)`;
  idempoten via `localStorage qr_client_key`; "Pesan lagi" mengosongkan
  identitas (privasi) & kembali ke langkah 1. Tanpa router (ramah Pages).
- Test: vitest `test/app.test.js` (21) + Playwright `tests/e2e/qr_customer.spec.js`
  (6) — teks kunci (`Kirim pesanan ke kasir`, `Referensi Q00099`,
  `Pesanan belum dibayar`, `Pesan lagi`, `QR tidak valid`) dipertahankan.

### Server (Supabase)
- Siklus kini: `PENDING → CLAIMED → COMPLETED/CANCELLED`; PENDING kadaluarsa
  → `EXPIRED` (lazy 2 jam). CHECK belum punya `PREPARING`.
- `qr_list_drafts()` hanya `PENDING`; `qr_complete_draft` mewajibkan
  `status='CLAIMED'` + `p_sale_id` (selesai = bayar).
- `qr_submit_draft` **sudah 7 param** (0018 terpasang di hosted 1 Nov 2026:
  `pay_intent`, `pay_method`, `customer_name`, `customer_phone`); lencana
  bayar diturunkan dari `sale_id`.
- `pos_checkout` idempoten (idempotency key) & menghitung total **di
  server** dari garis keranjang → sumber kebenaran uang.
- RLS `operator_all` → un-arsip (`archived_at = null`) **tanpa migrasi**.
- `get_public_menu` menyaring `is_active` + `archived_at is null`.

### POS Flutter (`apps/pos_flutter/`)
- "QR Masuk" = `QrInboxSheet` bottom sheet dari `PosPage`; polling 10 dtk &
  `_claimedDraftIds` (Set lokal `_PosPageState`) terkunci di halaman POS.
- `cartControllerProvider` (Notifier global) sudah lintas-halaman; keranjang
  mendukung edit qty, hapus baris, diskon %, metode bayar, nominal bayar.
- Setelah checkout sukses: `_completeClaimedDrafts(saleId)` → semua draft
  dalam set dikaitkan ke sale lalu set dikosongkan & keranjang dibersihkan
  (invarian: draft berstatus CLAIMED/PREPARING di perangkat ini pasti
  masih ada di keranjang, karena checkout selalu menghabiskan set).
- `AppDestination` 13 destinasi; PRD §2.2 & UAT-02 menyebut "tanpa halaman
  Pesanan" → tab baru = **evolusi panel QR Masuk** (catat §C4).
- Katalog: arsip ada, restore tidak ada, daftar arsip tak tampil.
- Belum ada `audioplayers` maupun `url_launcher`. Test suite **164**.

## A. Wizard Web (3 langkah + konfirmasi)

### A1. Alur & layar
```
[1 MULAI]      Dua kartu: "Bayar sekarang (ke kasir)" (DEFAULT)
               vs "Open Bill" (pesan dulu, bayar nanti).
               + Form identitas OPSIONAL: Nama · No. WhatsApp
                 (placeholder "Nama (opsional)", "No. WA (opsional)").
[2 PILIH MENU] Chip kategori sticky (Semua | Makanan | Minuman) → grid
               terfilter; sheet varian/catatan tetap; bar bawah
               "n item · Rp x — Lanjut" + akses keranjang.
[3 PEMBAYARAN] Ringkasan item; PAY_NOW → kartu CASH / QRIS / Transfer;
               OPEN_BILL → "Bayar nanti di kasir";
               ringkas identitas bila diisi ("Pesanan atas nama Budi");
               tombol "Kirim pesanan ke kasir" (teks dipertahankan).
[KONFIRMASI]   Kartu lama tetap (+ baris metode untuk PAY_NOW);
               "Pesan lagi" → langkah 1, client_key baru, form identitas
               KOSONG kembali (privasi: tidak menempel di perangkat lain).
```
- Indikator langkah + Kembali; keranjang bertahan bolak-balik; tanpa router
  (ramah GitHub Pages base `/SmartPOS/`).
- **Validasi identitas (ringan, jujur)**: nama ≤ 60 karakter; No. WA
  karakter `0-9 + - spasi`, 8–20 digit; salah format → blokir merah di
  bawah field + tombol kirim tetap aktif **hanya jika field disalahisi**
  (kosong = selalu boleh). Tidak ada validasi "nomor harus terdaftar".
- Nama/No. WA hanya dikirim saat submit; **tidak** disimpan di localStorage
  (hanya draft idempotensi yang disimpan).

### A2. Migrasi `20261031000018_qr_payment_pref.sql` (diperluas v4)
1. `qr_drafts` tambah kolom:
   - `pay_intent` (`PAY_NOW|OPEN_BILL`, null) + CHECK;
   - `pay_method` (`CASH|QRIS|TRANSFER`, null) + CHECK;
   - `customer_name text` (null; check `char_length ≤ 60`);
   - `customer_phone text` (null; check `char_length ≤ 24`).
2. `qr_submit_draft` → **6 param**, 4 baru **default null**
   (`p_pay_intent, p_pay_method, p_customer_name, p_customer_phone`) —
   klien lama & tes lama tetap sah. Validasi: nilai enum ketat; method
   wajib null kecuali PAY_NOW; nama/phone di-TRIM; panjang ditolak lewat.
3. `qr_draft_json`: sertakan `pay_intent`, `pay_method`, `customer_name`,
   `customer_phone`.
4. Grant ulang ke signature baru (anon + authenticated).
5. Test integrasi: kasus lama **utuh** + baru (submit ber-preferensi &
   identitas; identitas tidak ikut saat null; nama 61 karakter ditolak;
   method tanpa intent ditolak).
6. Deploy: dump backup `-Fc` → `supabase db push` → verifikasi REST.

### A3. Dampak POS & test web
- Kartu pesanan menampilkan preferensi + identitas (`Budi · 0812…`) —
  kasir tetap menekan konfirmasi bayar sendiri.
- vitest/e2e disesuaikan bersamaan (wizard, filter kategori, metode,
  field identitas opsional); teks kunci dipertahankan.

## B. Notifikasi masuk + suara

### B1. `QrInboxWatcher` di `lib/app/shell.dart`
- Polling 10 dtk pindah dari `PosPage` ke shell → berlaku dari halaman mana
  pun; satu sumber `qrDraftsProvider`.
- `ref.listen`: id draft **PENDING baru** → banner in-app "Pesanan baru dari
  Meja 3 · Q00042" (**ketuk → tab Pesanan**, §C) + mainkan nada bila aktif.
  Muat pertama = baseline (sunyi); deteksi in-memori; restart = baseline
  baru; status lain tidak memicu apa pun.

### B2. Sound & pengaturan
- Aset **Kenney "Notification Sounds" (CC0)** 3–5 `.ogg` di
  `apps/pos_flutter/assets/sounds/` + `README.md` sumber & lisensi.
- Dependency `audioplayers`; lapisan `NotifSound.play(id, volume)` dipancang
  di test (pola `shareSheetHandler`).
- Seksi **"Notifikasi pesanan"** di Settings (lokal, SharedPreferences):
  switch suara (default aktif), pilihan nada + **Pratinjau**, slider volume.
- ~5 test baru (bunyi+banner, baseline sunyi, off = sunyi, preferensi
  tersimpan, pratinjau).

## C. Tab "Pesanan" — alur Diterima · Diproses · Selesai · Bayar · WA

### C1. Model dua dimensi (logika inti)

**Dimensi 1 — Status pesanan (alur sajian):**
```
PENDING (Baru masuk)
   │ [Diterima]  → CLAIMED   : item draft dimasukkan ke keranjang POS
   │ [Batalkan]  → CANCELLED
CLAIMED (Diterima)          ── [Diproses] → PREPARING
PREPARING (Diproses)        ── [Tandai selesai] → COMPLETED, sale_id null
COMPLETED + sale_id null (Selesai, belum bayar)
   │ [Bayar] → pelunasan via checkout (Dimensi 2)
   └ [Hubungi WA] → wa.me prabayar (bila ada No. WA)
PENDING lewat 2 jam → EXPIRED (otomatis, lazy)
```

**Dimensi 2 — Status bayar (terpisah dari sajian):**
- `sale_id IS NULL` → **BELUM BAYAR** (lencana kuning).
- `sale_id TERISI` → **SUDAH BAYAR** (lencana hijau + metode preferensi);
  kartu lepas dari papan (final; riwayat di Riwayat Penjualan).
- Pembayaran **hanya** lewat `pos_checkout` (uang/omzet di jalur teruji).

**Invarian yang dijaga:**
1. **Selesai ≠ bayar** — `qr_complete_draft` boleh tanpa sale (Open Bill
   disajikan dulu, dibayar nanti).
2. **Pelunasan otomatis mengaitkan sale** — checkout di Kasir POS melunasi
   semua draft dalam `claimedDraftIds` perangkat ini (termasuk yang sudah
   COMPLETED-bayar-nanti); satu meja pesan 3× bayar 1× = satu sale mengaitkan
   3 draft.
3. **Tidak pernah "Selesai" tanpa melewati keranjang** — jalur ke PREPARING
   hanya lewat [Diterima].
4. **Uang tidak digerakkan tab Pesanan** — tab hanya mengubah status draft.
5. Papan = `PENDING`, `CLAIMED`, `PREPARING`, `COMPLETED yang sale_id null`.

### C2. Migrasi `20261031000019_qr_order_lifecycle.sql`
1. CHECK constraint status: drop + recreate
   `('PENDING','CLAIMED','PREPARING','EXPIRED','CANCELLED','COMPLETED')`.
2. **`qr_mark_preparing(p_draft_id)`** (baru): atomik
   `UPDATE … SET status='PREPARING' WHERE id=? AND status='CLAIMED'`;
   gagal → `draft_not_claimed`; audit `PREPARE`; grant authenticated.
3. **`qr_complete_draft(p_draft_id, p_sale_id bigint DEFAULT null)`**
   (drop + recreate, semantik baru):
   - `status IN ('CLAIMED','PREPARING')` → `COMPLETED`,
     `sale_id = p_sale_id` (boleh null);
   - `status='COMPLETED' AND sale_id IS NULL AND p_sale_id IS NOT NULL`
     → **kaitkan pelunasan**;
   - `status='COMPLETED' AND sale_id = p_sale_id` → idempoten;
   - selain itu → `draft_not_completable`.
4. `qr_cancel_draft`: `PENDING|CLAIMED|PREPARING`.
5. **`qr_list_drafts()`**: papan aktif —
   `status IN ('PENDING','CLAIMED','PREPARING') OR (status='COMPLETED' AND
   sale_id IS NULL)` urut `created_at`; lazy EXPIRED tetap.
   `qr_draft_json` (dari 0018) sudah membawa `status`, `sale_id`,
   preferensi & identitas → klien cukup menurunkan lencana dari `sale_id`.
6. Grant ulang semua signature yang berubah.
7. Test integrasi (lama utuh + baru): transisi tiap panah; complete tanpa
   sale; pelunasan setelah COMPLETED; retry idempoten; kaitkan sale berbeda
   ditolak; cancel dari PREPARING; list = papan aktif.

### C3. UI POS

**Destinasi baru & penggantian:**
- `AppDestination.orders('Pesanan', Icons.receipt_long_rounded, grup Utama)`
  — tepat setelah *Kasir POS*. **Tombol "QR Masuk" dihapus dari halaman
  POS** (`_QrBadge`, `_openQrInbox`, `QrInboxSheet` dipensiunkan/dihapus).
- **Badge navigasi**: jumlah **PENDING** pada ikon tab Pesanan (rail &
  NavigationBar) — pesanan baru ≠ antrean aktif.
- Navigasi: `_current` → `selectedDestinationProvider` (Notifier global)
  supaya banner & tombol [Bayar] bisa memindah tab dari mana pun.

**Halaman `lib/features/orders/orders_inbox_page.dart`:**
- **4 seksi**: **Baru masuk** (PENDING) · **Diterima** (CLAIMED) ·
  **Diproses** (PREPARING) · **Selesai — belum bayar** (COMPLETED, sale
  null). Refresh manual + otomatis dari watcher. Empty state jelas.
- **Kartu pesanan** (urut `created_at`):
  - Baris atas: `Meja 3 · Q00042` + **lencana bayar** (BELUM BAYAR /
    SUDAH BAYAR) + usia ("5 mnt lalu").
  - **Identitas** (bila diisi): `Budi · 081234567890` + tombol
    **[Hubungi WA]** (lihat C4).
  - Chip preferensi web: `Bayar sekarang · QRIS` / `Open Bill`.
  - Daftar item (qty×nama · varian · catatan) + **subtotal snapshot** +
    catatan kecil: "Total akhir = keranjang saat bayar (bisa bertambah)".
  - **Tombol aksi per status**:

| Status | Aksi |
|---|---|
| Baru masuk | **[Diterima]** · [Batalkan] |
| Diterima | **[Diproses]** · **[Bayar]** · [Batalkan] |
| Diproses | **[Tandai selesai]** · **[Bayar]** · [Batalkan] |
| Selesai — belum bayar | **[Bayar]** · [Hubungi WA] (bila ada no.) |

- **[Diterima]** = klaim atomik + item → keranjang; konflik harga & item
  tak tersedia tetap lewat **dialog persetujuan operator** (logika
  `PosPage._claimDraft` dipindah utuh ke `QrClaimService`).
- **[Diproses]** = `qr_mark_preparing`. **[Tandai selesai]** =
  `qr_complete_draft(id, null)` (Selesai, belum bayar).
- **[Batalkan]** = `qr_cancel_draft` (hanya PENDING/CLAIMED/PREPARING).

**[Bayar] — tindak lanjut pembayaran (rancangan baru v4):**
- Jika draft **belum** ada di `claimedDraftIds` perangkat ini → klaim dulu
  (dengan dialog konflik harga bila perlu) → item masuk keranjang.
- Lalu `selectedDestination = POS` — keranjang tampil, **adjustable**:
  edit qty, hapus baris, **tambah item apa pun dari katalog**, diskon %,
  pilih metode bayar, isi nominal (CASH). Itulah "tambahan untuk opsi
  lain": **penambahan dilakukan langsung di keranjang POS** — tanpa UI edit
  ganda di tab Pesanan (satu sumber keranjang, tidak ada dua bentuk edit
  yang bisa bentrok).
- Saat [Bayar] ditekan sementara draft sudah di set (pasti masih di
  keranjang — invarian C1.2) → cukup pindah ke Kasir POS.
- Checkout → `pos_checkout` (total final dari keranjang, bukan subtotal
  draft — jujur & eksplisit) → `claimedDraftIds` melunasi semua draft
  terkait → kartu berubah SUDAH BAYAR / lepas dari papan.
- **Open Bill adjustable penuh**: selama belum checkout, keranjang boleh
  berulang kali diedit; pesan tambahan dari web (draft baru, client key
  baru) tinggal [Diterima] lagi → menumpuk di keranjang yang sama → satu
  checkout melunasi semuanya.

**Ekstraksi & lintas-halaman:**
- `QrClaimService.claimDraft(ref, context, draft)` — dipakai tab Pesanan.
- `_claimedDraftIds` → **`claimedDraftIdsProvider`** (Notifier global);
  setelah checkout sukses: `qr_complete_draft(id, saleId)` semua id →
  set dikosongkan & keranjang dibersihkan (pola lama, dipindah dari
  `PosPage`). Gagal kaitkan tidak memengaruhi uang (sale tetap tersimpan).

### C4. Tindak lanjut via WhatsApp (baru v4)
- Dependency **`url_launcher`** (ringan, standar).
- Tombol **[Hubungi WA]** hanya muncul di kartu **BELUM BAYAR** dan
  ketika `customer_phone` terisi.
- Normalisasi nomor: buang spasi/`-`/`()`; `+62…`/`0…`/`8…` → format
  internasional `62…`. Nomor tidak valid → tombol nonaktif (tooltip
  "Nomor WA tidak valid").
- Buka `https://wa.me/<62…>?text=` dengan pesan prabayar, contoh:
  "Halo Budi, pesanan Anda di Meja 3 (Q00042) sudah selesai namun belum
  dibayar. Silakan lakukan pembayaran di kasir. Terima kasih 🙏".
- Dipancang di unit test (pola `sharePngHandler`): handler `waLaunchHandler`
  + URL hasil normalisasi diuji.

### C5. Penyelarasan dokumen
PRD §2.2 ("tanpa halaman Pesanan") & UAT-02 ("panel QR Masuk, tidak di
halaman pesanan") — tab Pesanan = **evolusi panel QR Masuk** (satu operator;
alur klaim/cek harga/uang tidak berubah, hanya rumah UI). Identitas
nama/WA: **opsional, untuk penagihan, tidak dipakai untuk hal lain** —
dicatat di `docs/api-contracts.md` (skema draft + 4 tombol + 2 dimensi) +
PRD changelog.

### C6. Test Flutter
- `orders_inbox_page_test.dart` (pengganti `qr_inbox_sheet_test`): 4 seksi;
  [Diterima] → claim + item ke keranjang; [Diproses] → mark_preparing;
  [Tandai selesai] → complete tanpa sale; [Batalkan] → cancel; **[Bayar]**
  → klaim bila perlu + pindah ke POS; lencana BELUM/SUDAH BAYAR dari
  `saleId`; identitas & chip preferensi tampil; **[Hubungi WA]** → handler
  terpanggil dengan URL benar; nomor tidak valid → nonaktif; dialog konflik
  harga; mapping error; empty state.
- `claimed_drafts_provider_test.dart`: checkout → complete semua id;
  pelunasan draft COMPLETED-bayar-nanti ikut; gagal kaitkan tidak melempar
  ke alur bayar.
- `page_layout_test`/`shell_test`: destinasi Pesanan; badge PENDING; banner
  → pindah tab; watcher tidak membunuh state halaman.
- 164 test lama tetap lulus (yang menyentuh tombol QR Masuk disesuaikan
  searah).

## D. Keluarkan dari arsip (produk & kategori)

- **Repository** (`catalog_repository.dart`): `restoreProduct(id)` /
  `restoreCategory(id)` → `update({'archived_at': null})` — **tanpa
  migrasi** (RLS sudah izinkan).
- **Halaman katalog**: chip filter **Aktif | Arsip**; produk arsip + aksi
  **"Keluarkan dari arsip"** (ikon `unarchive`); sheet kategori menampilkan
  kategori arsip (abu-abu) + ikon un-archive.
- **Provider**: `productsProvider`/`categoriesProvider` mendukung
  `includeArchived` (halaman katalog); POS & menu web tetap hanya aktif.
- **Test** (~4 baru): un-arsip memanggil repo + refresh; arsip hanya tampil
  di filter Arsip; kategori kembali ke pilihan produk; POS tak menampilkan
  produk arsip.

## E. Seed menu — SELESAI ✅

- `supabase/seed/seed_menu_waroeng.sql` (commit `7e58a85`): **2 kategori
  besar** (Makanan 26 · Minuman 49) sesuai permintaan usaha; 72 menu aktif +
  3 add-on nonaktif (harga menyusul, diaktifkan via Menu & Harga); modifier
  "Besar +Rp5.000" (Mie Nasi Goreng & Nasi Goreng); varian panas diberi
  imbuhan "Panas". Live di hosted; terverifikasi di H13Pro.

### Foto menu (1 Nov 2026) — 9 foto live

Sumber `menu/*.webp` (lokal, TIDAK masuk Git — cukup unggah sekali; salinan
di bucket Storage hosted). Diunggah via sesi operator (bukan service role)
ke bucket `product-photos`, `photo_url` diisi untuk 9 produk: Ayam Bakar,
Ayam Geprek + Nasi, Ayam Kremes + Nasi, Mie Goreng, Mie Nasi Goreng,
Mie Rebus, Mie Tarempa, Nasi Goreng, Seblak Komplit. Terverifikasi lewat
`get_public_menu` anon (90 produk aktif, 9 dengan foto).

Dua foto **dilewati karena lisensi** (Prompt.md mewajibkan foto legal):
`nasi_telur_dadar.webp` (watermark iStock) dan
`pngtree-indonesian-seblak-…webp` (lisensi PNGTree) — Nasi Telur Dadar &
Seblak Biasa masih tanpa foto; ganti dengan foto asli usaha.
Catatan kualitas: 5 foto punya latar pola catur bekas transparansi PNG dan
3 foto berresolusi kecil (±320px) — cukup untuk thumbnail, ganti bila ada
foto asli. Web QR (`App.vue`) belum menampilkan `photo_url` (ikut Fase 3).

## Fase eksekusi (sisa)

| # | Fase | Keluaran | Verifikasi |
|---|---|---|---|
| 1 | Migrasi 0018 (preferensi bayar + identitas) + test integrasi → hosted | kontrak draft v4 | **SELESAI** 1 Nov 2026 — 51 PASS, 0 FAIL |
| 2 | Migrasi 0019 (lifecycle 2 dimensi) + test integrasi → hosted | PREPARING, complete longgar, papan | PG 5433 hijau |
| 3 | Wizard web (termasuk form nama/WA) + filter kategori + vitest/e2e | deploy Pages otomatis | **SELESAI** 1 Nov 2026 — vitest 21/21, e2e 6/6, build lulus |
| 4 | Tab Pesanan (aksi + [Bayar] + [Hubungi WA]) + QrClaimService + claimedDraftIdsProvider + banner navigasi | alur Diterima–Diproses–Selesai–Bayar–WA | test Flutter |
| 5 | Sound CC0 + audioplayers + seksi pengaturan | suara & preferensi | test Flutter |
| 6 | Un-arsip produk & kategori + tampilan Arsip | arsip pulih | test Flutter |
| 7 | analyze 0 + full test + release build → H13Pro | uji E2E nyata | HP pesan (isi nama+WA) → tablet bunyi → alur status → tambah item → lunasi → [Hubungi WA] bila perlu |
| 8 | Docs (api-contracts, PRD catatan, release-notes, sprint-log, handover) + push | rilis tercatat | CI 4 job hijau |

**Dependency baru**: `audioplayers` (B), `url_launcher` (C4).

## Risiko & mitigasi

- **Test web putus** → perubahan alur/teks hanya bersamaan dengan
  penyesuaian vitest+e2e pada commit yang sama.
- **Klien lama** → 0018/0019 param default null; drop-create fungsi satu
  migrasi; kasus integrasi lama dipertahankan utuh.
- **Semantik complete berubah** → pemanggil lama (CLAIMED + sale_id) tetap
  sah; retry idempoten; kaitkan sale berbeda ditolak.
- **Subtotal draft ≠ total bayar** → snapshot draft tetap ditampilkan +
  catatan eksplisit "total akhir = keranjang saat bayar" (jujur).
- **Nomor WA salah format** → tombol nonaktif; normalisasi 62…; tanpa
  validasi registrasi (tidak menjamin nomor aktif — jujur).
- **Privasi nama/WA** → opsional, hanya untuk penagihan di perangkat kasir;
  tidak disimpan di localStorage web; dicatat di kontrak API.
- **Draft diklaim perangkat lain** → pelunasan tidak otomatis (satu
  operator per PRD); kartu tetap jujur "belum bayar".
- **Papan melebar** → badge hanya PENDING; papan otomatis menyaring
  sudah-bayar/batal/kadaluarsa.
- **Suara mengganggu** → default aktif tapi bisa dimatikan/diganti; hanya
  draft BARU yang membunyikan.
- **Arsip tak sengaja** → un-arsip tersedia; arsip = timestamp, bukan hard
  delete.

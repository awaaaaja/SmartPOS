# Catatan kandidat MVP 1.0.0+1 — 27 Oktober 2026

**Status: QA/PARTIAL, bukan rilis produksi.** Retry backend/klien QA lulus;
signing, distribusi klien, perangkat target dan pemulihan Supabase penuh belum lulus.

## Perubahan Sprint 06

- Perbaikan overflow HP pada header meja, katalog, stok, resep, pembelian,
  kalkulator energi, dan kartu laporan. POS tablet 1024×768 tetap dua kolom
  setelah ruang sidebar dikurangi.
- Keranjang HP mengikuti perubahan jumlah; pembayaran memakai jumlah terbaru,
  dropdown tidak melebar keluar layar, dan form dapat digulir saat keyboard terbuka.
- Pengaturan membaca profil dan tarif aktual dari Supabase (read-only), bukan
  placeholder yang menjanjikan sprint lama. Teks dashboard diperbarui.
- Regresi backend tidak lagi mengasumsikan pajak/layanan nol. Konfigurasi usaha
  tidak diubah untuk meluluskan tes. Kata sandi tes wajib dari environment.
- Analyzer 0 issue; ekspor CSV web memakai `package:web` yang sudah ada dalam
  dependency tree. Bukan penambahan paket fitur baru.
- Debug signing tidak lagi dipakai untuk release. Signing opsional dari empat
  environment variable; tanpa keystore hasil build **unsigned**.
- Backup/restore bisnis diuji di staging PostgreSQL lokal; scan publik,
  pengukuran latensi, dan bukti browser disimpan di `docs/evidence/sprint06/`.

## Perbaikan K06-01 — retry refund & koreksi stok (27 Oktober 2026)

- **Sebelum**: dua permintaan identik menggandakan mutasi (refund Rp100 → Rp200,
  koreksi +1 → +2) karena tidak ada identitas permintaan.
- **Server** (`20261027000013_mutation_retry.sql`, **sudah diterapkan ke hosted**):
  `pos_refund` dan `inv_adjust_stock` kini mewajibkan `p_idempotency_key`
  (8–128 karakter), mengunci per key, menyimpan request+respons atomik di
  `mutation_requests` (RLS aktif, tanpa baca untuk anon/authenticated), dan
  menolak payload berbeda pada key sama dengan `idempotency_key_conflict`.
  Implementasi lama dipindah ke `*_once` tanpa grant. Tanpa key →
  `missing_idempotency_key` (gagal tertutup, bukan dobel).
- **Klien**: identitas + payload disimpan di penyimpanan lokal **sebelum** RPC
  dan dipakai ulang saat respons hilang atau form dibuka kembali; form refund dan
  koreksi/waste tidak ditutup selama submit, isian terkunci selama permintaan
  tertunda, tombol berubah menjadi "Ulangi … yang sama".
- **Sampingan yang ikut diperbaiki**: koreksi `ADJUSTMENT` negatif (stok turun)
  sebelumnya ditolak oleh validasi; kini divalidasi lewat magnitudo. Pesan error
  jaringan tidak lagi mengklaim "Transaksi belum tersimpan" — status justru
  belum terkonfirmasi.
- **Bukti**: `docs/evidence/sprint06/retry-fix.json` (replay hosted dalam
  `BEGIN/ROLLBACK` +100/+1, probe anon 401, 9 tes SQL, 148 tes Flutter,
  regresi hosted 212 PASS 0 FAIL). Detail: `docs/sprint-log.md` Sprint 06.
- Empat celah sisa ditutup pada lanjutan `0014` di bawah. Hasil `0013` di atas
  dipertahankan sebagai riwayat, bukan status akhir cakupan retry.

## Lanjutan K06-01 — pembelian, produksi, biaya dan energi

- Migrasi `20261027000014_mutation_retry_rest.sql` **terpasang di hosted**.
  Keempat RPC CREATE/mutasi kini wajib key 8–128 karakter; helper internal
  deduplikasi dan `*_once` tidak dapat dipanggil klien. UPDATE biaya tetap
  tanpa cache/key agar edit berikutnya tidak terkunci; izin operator diperiksa.
- Klien memakai penyimpanan retry yang sama, dengan pembandingan list/map
  mendalam. Form mengembalikan isian lama yang terkunci setelah timeout/relaunch.
  Tidak ada tombol buang pending atau outbox baru; konfirmasikan replay dahulu.
- Audit RPC lain: checkout/QR sudah memakai key, penerimaan/kas memakai guard
  status dan alokasi memakai upsert. Tidak menambah fitur baru.
- **Bukti** `retry-rest-fix.json`: 15 SQL, 155 Flutter, analyzer 0 issue,
  regresi hosted **212 PASS, 0 FAIL**. Replay hosted rollback empat RPC = satu
  efek per key; konflik ditolak, anon 401, fixture probe tersisa 0.
- Smoke Chrome listrik: respons sukses sengaja dihilangkan, browser dimuat ulang,
  lalu retry menghasilkan `idempotent_replay=true`, estimate #22/expense #42 tetap
  satu, Rp2.880 ESTIMATED. Tiga screenshot tambahan; **bukan uji Android/jaringan fisik**.
- Klien lama tanpa key akan gagal tertutup setelah migrasi. Distribusi klien baru
  bertanda tangan tetap wajib sebelum operator memakai aplikasi.

## Artefak lokal

| Artefak | Hasil |
|---|---|
| `apps/pos_flutter/build/app/outputs/flutter-apk/app-release.apk` | 58.281.930 byte; **UNSIGNED**, belum dapat dipasang; memuat perbaikan `0013`–`0014` |
| `apps/pos_flutter/build/web/` | Build release web berhasil (164,4 s), memuat perbaikan `0013`–`0014`; hanya untuk QA |
| `apps/qr_web/dist/` | Build Vue berhasil; hosting HTTPS permanen belum ada |

SHA-256 APK (setelah rebuild K06-01):
`6afbfbb6cf3d36763bdcfd512113304a2f0e0aabb60cd0c9014fc3725d0a7289`.
Artefak sebelumnya (`a4a9588e…f958`) digantikan; hanya memuat fix refund/koreksi,
bukan empat RPC lanjutan. Build terbaru lulus percobaan pertama dengan JVM IPv4.
`apksigner verify` menolak APK unsigned (exit 1), sesuai status artefaknya.
File build/backup tidak masuk Git; keberadaannya lokal, bukan tautan distribusi.

## Fitur dan batasan

Tersedia: login satu operator; katalog/harga/modifier; kasir dan struk digital;
draft QR → keranjang → pembayaran; stok/pembelian/resep-HPP; energi dan biaya
estimasi/aktual; alokasi biaya; kas shift; riwayat/refund; laporan/CSV web.
Transfer/QRIS **diverifikasi manual**, bukan konfirmasi PSP otomatis.

Tidak dibuat: Dapur, Pesanan terpisah, Pegawai, Multi-Cabang, Subscription,
SaaS, AI/ML. Printer belum dipilih/diuji; offline/outbox tidak dicakup. CSV Android
masih berkas sementara aplikasi, belum share/download ke folder pengguna.
Profil/tarif hanya ditampilkan; perubahan melalui pengelola Supabase.

Blocker dan prosedur lanjutan: [serah terima](handover.md).

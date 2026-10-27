# Catatan kandidat MVP 1.0.0+1 — 27 Oktober 2026

**Status: QA/PARTIAL, bukan rilis produksi.** Gate uang/stok, signing,
perangkat target, dan pemulihan Supabase penuh belum lulus.

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
- **Belum dicakup**: `inv_create_purchase`, `inv_produce_batch`, biaya
  energi/expense dan alokasi belum punya pola key serupa; APK lama (tanpa
  perbaikan klien) akan gagal tertutup setelah migrasi — build ulang wajib.

## Artefak lokal

| Artefak | Hasil |
|---|---|
| `apps/pos_flutter/build/app/outputs/flutter-apk/app-release.apk` | 58.183.626 byte; **UNSIGNED**, belum dapat dipasang; sudah diperbarui memuat perbaikan K06-01 |
| `apps/pos_flutter/build/web/` | Build release web berhasil (155 s), memuat perbaikan K06-01; hanya untuk QA |
| `apps/qr_web/dist/` | Build Vue berhasil; hosting HTTPS permanen belum ada |

SHA-256 APK (setelah rebuild K06-01):
`a4a9588e4cd1443429bf0434a5b61db19e8d33448d81983bfe98aa1ad6e8f958`.
Artefak sebelumnya (`0a51b209…64604b`) sudah digantikan dan **tidak** memuat
perbaikan retry — jangan dipakai. Build pertama percobaan lama gagal DNS Google
Storage; percobaan JVM IPv4 berhasil (kali ini lulus percobaan pertama).
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

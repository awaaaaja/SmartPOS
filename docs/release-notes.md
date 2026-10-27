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

## Artefak lokal

| Artefak | Hasil |
|---|---|
| `apps/pos_flutter/build/app/outputs/flutter-apk/app-release.apk` | 58.068.938 byte; **UNSIGNED**, belum dapat dipasang |
| `apps/pos_flutter/build/web/` | Build release web berhasil; hanya untuk QA |
| `apps/qr_web/dist/` | Build Vue berhasil; hosting HTTPS permanen belum ada |

SHA-256 APK:
`0a51b2095ce8ca6ea12efa5c14a8df2f2dc7dfa4759b74bf2f3715841864604b`.
Build pertama gagal DNS Google Storage; percobaan JVM IPv4 berhasil.
`apksigner verify` menolak APK unsigned, sesuai status artefaknya.
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

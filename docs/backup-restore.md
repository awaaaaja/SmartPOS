# Backup dan latihan restore Sprint 06

## Bukti yang sudah ada

`evidence/sprint06/backup-restore.json`: `pg_dump` PostgreSQL 18 dari Supabase
ke arsip custom, lalu `pg_restore --exit-on-error` ke database lokal terisolasi
`s06_restore`. **25 tabel public** cocok jumlah baris dan checksum seluruh isi;
total sale/refund cocok; **23 policy RLS** pulih. Anon membaca 0 sale.
`non-operator-rls.json` membuktikan akun authenticated non-operator tidak melihat
sale/settings dengan stub JWT lokal.

Arsip privat berada di `/tmp/opencode/smart-pos-backups/` (direktori 0700,
file 0600): `s06-business.dump`, `s06-auth-users.dump`. **Tidak masuk Git**.
Lokasi sementara ini bukan retensi backup; pemilik harus memindahkan ke media
terenkripsi berakses terbatas di luar mesin sebelum mengandalkannya.
Jangan menaruh arsip Auth ke evidence/tiket/chat.

Ini **bukan** latihan disaster recovery Supabase penuh: hanya `public`,
`extensions` dan tabel `auth.users`; tidak ada identities/sessions GoTrue lengkap,
Storage bucket objects/foto, konfigurasi Auth, secrets atau hosting. Fungsi
`auth.uid/jwt` staging berupa stub, bukan layanan Auth yang dapat login.

## Prosedur pengulangan (staging saja)

1. Tentukan waktu maintenance/snapshot. Simpan hostname/user/database pada
   environment libpq; minta password interaktif atau secret manager, jangan
   memasukkannya ke source/command URL/log. Pastikan koneksi TLS.
2. Arsip custom bisnis dan Auth/users harus diperlakukan sensitif:

   ```bash
   umask 077
   pg_dump --format=custom --schema=public --schema=extensions \
     --no-owner --no-acl --file=s06-business.dump
   pg_dump --format=custom --table=auth.users \
     --no-owner --no-acl --file=s06-auth-users.dump
   sha256sum s06-business.dump s06-auth-users.dump
   ```

   Dua dump ini bukan satu snapshot lintas-schema saat write berlangsung.
   Untuk backup rilis, gunakan full platform backup/snapshot konsisten yang
   mencakup Auth dan salinan Storage; jangan sekadar mengandalkan contoh subset ini.
3. Buat database staging **baru/kosong**. Pada PostgreSQL polos, siapkan role
   `anon`/`authenticated`, schema/fungsi Auth stub, dan pgcrypto di `extensions`.
   Jangan menjalankan stub pada proyek Supabase sungguhan.
4. Restore `auth.users`, kemudian bisnis menggunakan `pg_restore --no-owner
   --no-acl --exit-on-error --dbname=STAGING`. Karena schema `public`/`extensions`
   sudah disiapkan di staging polos, buat TOC `pg_restore -l` dan keluarkan hanya
   entri `SCHEMA - public`/`SCHEMA - extensions` dari restore-list; jangan menghapus
   table/data/policy. Restore bisnis dengan `--use-list=restore.list`.
5. Bandingkan seluruh tabel: count + checksum JSON terurut, sequence state,
   total sale/refund, ledger/saldo dan jumlah policy. Pakai `PGOPTIONS='-c timezone=UTC'`
   pada sumber dan target agar representasi timestamp checksum sama. Hash bukan
   pengganti pemeriksaan uang/stok. Sprint 06 memeriksa isi tabel dan policy;
   verifikasi sequence/cold checkout setelah restore masih harus ditambahkan.
6. Di Supabase staging lengkap, uji login operator, penolakan anon/non-operator,
   foto produk, quote/checkout/refund, replay key, stok dan laporan; simpan bukti
   tanpa JWT/password/isi Auth. Baru setelah itu nilai gate full-restore.
7. Jadwalkan backup harian dan sebelum rilis, enkripsi, retensi di luar mesin,
   uji restore berkala dan penanggung jawab pemulihan. **Belum dijadwalkan otomatis**.

Tidak ada restore/cutover ke database hosted aktif pada Sprint 06 ini.

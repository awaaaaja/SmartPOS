# Serah terima QA MVP — 27 Oktober 2026

**Keputusan: BELUM SIAP PRODUKSI. Sprint 06 PARTIAL.** Dokumen ini adalah
paket QA dan SOP latihan, bukan persetujuan go-live operator.

## 1. Blocker / known issues

| ID | Prioritas | Temuan dan tindakan sebelum rilis |
|---|---|---|
| K06-01 | P0 → **SELESAI untuk refund & koreksi stok; audit lanjutan terbuka** | Dulu: refund Rp100 identik dua kali menghasilkan Rp200, koreksi +1 dua kali menghasilkan +2. Kini `pos_refund`/`inv_adjust_stock` mewajibkan `p_idempotency_key` (8–128 char), mengunci per key, menolak payload berbeda pada key sama, dan menyimpan respons atomik di `mutation_requests`; form Flutter menyimpan key sebelum RPC dan memakainya ulang saat timeout/buka-ulang. **Migrasi `20261027000013` sudah diterapkan ke hosted** (lihat `evidence/sprint06/retry-fix.json`): uji replay di dalam `BEGIN/ROLLBACK` menghasilkan refund +100 dan stok +1, probe anon 401, regresi hosted 212 PASS, 9 tes SQL lokal lulus, 148 tes Flutter lulus. **Sisa:** (a) audit RPC mutasi lain (`inv_create_purchase`, `inv_produce_batch`, expense/energi, alokasi) belum punya kunci — gate penuh baru dicentang setelah ini; (b) build & distribusikan klien baru, karena klien lama tanpa key kini gagal tertutup (`missing_idempotency_key`); (c) bukti jaringan putus di tablet. Guard tombol saja bukan jaminan server. |
| K06-02 | P0 | APK unsigned, tidak dapat dipasang. Pemilik harus menyediakan keystore, menguasai backup key/password, membangun ulang dan memverifikasi signature. Jangan distribusikan artefak unsigned sebagai release. |
| K06-03 | P0 | Tidak ada Android/tablet/emulator terhubung. Bukti Sprint 06 berasal dari Chrome dan widget test, **bukan** perangkat target. Wajib instalasi, keyboard, rotasi, jaringan putus, transaksi, laporan dan cold-start di tablet. |
| K06-04 | P0 | Restore bisnis lokal lulus, tetapi GoTrue lengkap (identities/sessions), Storage/foto, login staging cloud dan retensi backup terenkripsi di luar mesin belum dibuktikan. Tidak ada crash-reporting terkelola; observabilitas release belum diinstrumentasi/diuji. |
| K06-05 | P0 | Password operator dahulu ter-commit dalam tes. Default itu sudah dihapus, **bukan** riwayat Git. Rotasi password operator dan cabut sesi lama sebelum distribusi/push; rotasi kredensial lain yang pernah dibagikan. Jangan menaruh nilai pengganti dalam source/log. |
| K06-06 | P0 | `QR_WEB_URL` belum diisi pada build QA. Sediakan hosting HTTPS permanen, build ulang dan cetak/rotate QR setelah URL final. Tunnel lama bukan deployment. |
| K06-07 | P1 | Latensi jaringan tidak stabil; dashboard mencapai 6,05 dtk (termasuk retry transport). Tidak ada bukti FPS/performa native. Ukur lagi pada tablet dan jaringan operasional sebelum menyatakan lancar. |
| K06-08 | P1 | Printer/Bluetooth belum diuji; CSV Android belum dapat dibagikan dari UI; offline tidak tersedia; PSP belum terintegrasi; Pengaturan read-only. Sampaikan batasan kepada operator. |

Bukti kasus retry: `evidence/sprint06/retry-gap.json`; hanya database lokal
terisolasi, dibungkus `BEGIN/ROLLBACK`, tidak mengubah uang/stok hosted.

### Urutan rollout K06-01 (status: langkah 1–3 selesai)

1. **Database dulu** — ✅ **selesai**: `supabase/migrations/20261027000013_mutation_retry.sql`
   diterapkan ke hosted lewat `supabase db push --db-url "$SUPABASE_DB_URL"`.
   Migrasi ini menamai ulang implementasi lama menjadi `*_once` (hanya
   postgres/service_role) dan membuat wrapper baru bertanda tangan
   `p_idempotency_key`; **tidak** menyentuh baris historis. Definisi lama
   disimpan untuk rollback di `/tmp/opencode/smart-pos-backups/pre-0013-functions.sql`.
2. **Klien baru** — ✅ kode selesai, **belum didistribusikan**: klien lama tanpa
   key kini menerima `missing_idempotency_key` pada refund/koreksi (gagal tertutup,
   tidak dobel). Build ulang APK/web dan pasang sebelum operator memakai aplikasi
   lama; APK saat ini masih **unsigned** (K06-02).
3. **Verifikasi** — ✅ selesai: `tests/integration/test_mutation_retry.py`
   (9 tes, database segar dibuat/dihapus tes) lulus; replay di hosted dibungkus
   `BEGIN/ROLLBACK` (refund +100, stok +1, konflik payload ditolak, sisa baris 0);
   regresi hosted 212 PASS. Verifikasi aplikasi di perangkat target masih menunggu
   K06-03.
4. **Audit lanjutan** — ❌ **belum**: RPC mutasi lain (`inv_create_purchase`,
   `inv_produce_batch`, expense/energi, alokasi) belum memiliki pola key yang
   sama; tutup sebelum gate "semua mutasi uang/stok aman terhadap retry" dicentang.

Jika respons mutasi uang/stok tidak jelas, **jangan mengulang secara buta**:
periksa struk/ledger/audit bersama pengelola. Setelah migrasi terpasang, retry
dengan isian identik aman; permintaan ulang dengan isian **berbeda** akan
ditolak `idempotency_key_conflict` — buka form baru untuk operasi berikutnya.

## 2. Setup Supabase

1. Gunakan proyek staging/produksi yang tepat. Simpan DB URL hanya di environment
   pengelola. Matikan pendaftaran publik; buat satu akun operator melalui Auth.
2. Terapkan seluruh migrasi berurutan (`0001`…`0013`), jangan mengedit migrasi lama:

   ```bash
   supabase db push --db-url "$SUPABASE_DB_URL"
   ```

3. Isi satu record `business_settings` (id=1): nama, alamat,
   `timezone='Asia/Jakarta'`, `operator_email` harus cocok dengan email Auth.
   Tarif berupa **pecahan**: pajak 7,5% = `0.075`, layanan 2,5% = `0.025`.
   Nilai tersebut contoh, bukan penetapan tarif usaha. Pengelola menyetujui tarif.
4. Untuk proyek kosong saja, isi record ini lewat SQL Editor/seed yang ditinjau;
   jangan mereset database yang sudah bertransaksi. `supabase/seed/seed_dev.sql`
   dan suite integrasi membuat data uji — **bukan** prosedur persiapan produksi.
5. RLS harus aktif. Anon hanya menggunakan `get_public_menu`/`qr_submit_draft`
   dengan token meja sah; akun non-operator tidak boleh membaca data internal.
   Jalankan ulang probe staging setelah perubahan Auth/migrasi.
6. Build Vue dari `apps/qr_web/` dengan `VITE_SUPABASE_URL` dan
   `VITE_SUPABASE_PUBLISHABLE_KEY` sesuai `.env.example`. Deploy `dist/` ke HTTPS,
   lalu masukkan URL itu sebagai `QR_WEB_URL` ketika membangun Flutter.
7. Kunci publishable/anon boleh di klien. DB password, service-role/server key,
   token login operator dan keystore tidak boleh masuk Flutter/Vue/Git.

## 3. Build, signing dan pemasangan Android

Versi saat ini `1.0.0+1`; application ID `com.waroengmejeng.pos_flutter`;
minSdk 24 (Android 7), targetSdk 36; ARMv7, ARM64 dan x86_64. Belum diuji di device.
Pemilik membuat/menyimpan signing key secara lokal (jangan mengirimnya ke chat).
`keytool -genkeypair` sebaiknya meminta password interaktif. Backup keystore dan
password terpisah dengan akses terbatas; kehilangan key menghambat update aplikasi.

Gradle membaca environment berikut, tanpa fallback debug key:

```bash
export MEJENG_KEYSTORE_PATH=/lokasi/absolut/release.jks
export MEJENG_KEY_ALIAS=mejeng
read -rsp 'Store password: ' MEJENG_STORE_PASSWORD
export MEJENG_STORE_PASSWORD
read -rsp 'Key password: ' MEJENG_KEY_PASSWORD
export MEJENG_KEY_PASSWORD
```

Dari `apps/pos_flutter/`, setelah environment URL/key publik/hosting diisi:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
  --dart-define=QR_WEB_URL="$QR_WEB_URL"
```

Jika DNS Java bermasalah, percobaan lokal berhasil dengan
`JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true`; jangan menonaktifkan TLS.
AAB hanya diperlukan bila memilih distribusi Play; belum dibangun.

```bash
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
adb devices -l
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Lanjut ke install **hanya jika verifikasi signature exit 0** dan fingerprint cocok
dengan key pemilik. APK unsigned Sprint 06 gagal verifikasi secara sengaja.
Update membutuhkan key sama; build debug lama tidak dapat ditimpa release dengan
key berbeda. Jangan uninstall/clear data atau downgrade paksa tanpa memastikan
keranjang/draft/sesi dan backup aman. Jangan mengirim password lewat argumen build.

## 4. Migrasi, backup dan rollback

- Sprint 06 ini tidak menambah migrasi; schema terakhir tetap `0012`.
- Backup sebelum migrasi/rilis. Latihan yang sudah dilakukan dan batasannya:
  [backup-restore.md](backup-restore.md).
- Rollback aplikasi: gunakan build bertanda tangan sebelumnya yang sudah diuji,
  key yang sama, serta versi/build-code yang sesuai mekanisme distribusi. Verifikasi
  kompatibilitas schema terlebih dahulu; jangan menjanjikan downgrade `adb` otomatis.
- Rollback DB: utamakan migrasi perbaikan maju. Restore dahulu ke staging kosong,
  reconcile uang/stok, hentikan write saat cutover yang disetujui pemilik. Jangan
  menimpa database aktif atau menghapus transaksi setelah backup tanpa rekonsiliasi.

## 5. SOP latihan operator

1. Login operator; periksa tarif di Pengaturan, menu aktif, stok dan kas awal.
2. Kasir langsung: pilih menu/modifier, cek jumlah/catatan/diskon, buka Bayar,
   cocokkan quote server, pilih metode, isi nominal. Transfer/QRIS wajib diperiksa
   manual. Struk final menandakan sale tersimpan; catat nomor struk bila bermasalah.
3. QR: pelanggan mengirim **draft, belum dibayar**. Di POS buka QR Masuk → Ambil;
   konfirmasi perubahan harga/item habis, periksa keranjang, lalu bayar seperti biasa.
4. Pembelian diterima menambah stok sekali; ORDERED belum menambah. Resep dan
   produksi batch mengikuti mode stok. Koreksi/waste wajib alasan. Mengulang
   koreksi yang sama setelah jaringan putus/respons hilang aman — tombol
   "Ulangi mutasi yang sama" memakai identitas lama dan efek terjadi sekali;
   tetap hentikan retry pada mutasi lain yang belum punya kunci (lihat K06-01).
5. Refund lewat detail riwayat: cek nominal dan alasan, lalu cocokkan net sales.
   Ulangi refund yang sama aman (identitas disimpan sebelum kirim); isian berbeda
   pada kunci lama ditolak `idempotency_key_conflict` — buat operasi baru lewat
   form normal, jangan menimpa permintaan tertunda.
6. Energi adalah ESTIMASI, bukan tagihan AKTUAL. Periksa alokasi tidak melebihi
   sumber. Laporan menyajikan estimasi margin, bukan klaim laba bersih.
7. Tutup shift: hitung uang fisik; bandingkan expected CASH (bukan transfer/QRIS),
   masukkan actual dan alasan selisih. Uji ini di staging sebelum kas operasional.
8. Offline: hentikan checkout, pulihkan jaringan dan periksa status transaksi.
   Keranjang bukan backup; tidak ada outbox/sinkronisasi offline.

## 6. Checklist UAT dan persetujuan

| Gate | Bukti/status saat ini |
|---|---|
| Tanpa Dapur/Pesanan/Pegawai/Multi-Cabang/SaaS/AI | Lulus pemeriksaan navigasi/source dan tes shell |
| Semua mutasi uang/stok aman terhadap retry | **PARTIAL K06-01**: `pos_checkout`, QR submit, `pos_refund`, `inv_adjust_stock` lulus uji (9 SQL + 16 tes Flutter + regresi hosted 212 PASS) dan migrasi `0013` sudah terpasang; RPC mutasi lain belum diaudit |
| QR mengakui draft, bukan pembayaran | Lulus browser: Q00114, tulisan “Pesanan belum dibayar” |
| Kas/omzet dari sale final | 212 pemeriksaan backend lulus; dua smoke sale web, bukan draft pending |
| Backup/auth/manual tablet | **PARTIAL** restore bisnis lokal + login web; Auth/Storage penuh dan tablet belum |
| Batasan printer/offline/PSP dinyatakan | Lulus dokumentasi; bukan bukti perangkat/integrasi |
| APK signature dan instalasi | **BELUM** unsigned; tidak ada device |
| Operator menyelesaikan transaksi sendiri | **BELUM**; SOP tersedia, latihan/persetujuan manusia belum dilakukan |

Persetujuan pemilik/operator: **belum diberikan**. Tanggal/device/hasil latihan
diisi setelah K06-02…K06-06 dan audit lanjutan K06-01 selesai. S01-08 CI hosted
juga masih menunggu remote GitHub; hasil lokal bukan klaim GitHub Actions hijau.

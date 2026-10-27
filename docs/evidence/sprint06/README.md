# Evidence Sprint 06 — QA, bukan persetujuan produksi

Semua PNG di sini berasal dari **Chrome Linux dengan build Flutter web/Vue**.
Bukan screenshot Android fisik/emulator. Widget test memakai viewport logis;
browser HP menggunakan emulasi 390×844, bukan pengujian hardware.

| File | Bukti |
|---|---|
| `01_dashboard_tablet_web.png` | Dashboard aktual, brand #930031, tanpa modul terlarang |
| `02_pos_tablet_dua_kolom_web.png` | POS 1024×768: sidebar + katalog + keranjang bersamaan |
| `03_bayar_pajak_layanan_web.png` | Subtotal 7.000 + 525 pajak + 175 layanan = 7.700; bayar 10.000 |
| `04_sale_manual_final_web.png` | Struk manual MJ-261027-0057; kembali 2.300 |
| `05_qr_draft_belum_dibayar_web.png` | Vue 390×844: Q00114 dikirim tetapi belum dibayar |
| `06_qr_masuk_web.png` | Draft Q00114 diterima POS, item/catatan/subtotal benar |
| `07_qr_sale_final_web.png` | Checkout draft menjadi sale MJ-261027-0058 |
| `08_pos_hp_web.png` | Flutter 390×844: katalog dan bottom navigation |
| `browser-smoke.json` | Dua sale final dan Q00114 COMPLETED cocok DB; meja QA dinonaktifkan |
| `csv-browser.json` | Klik Ekspor CSV aktual menghasilkan Blob UTF-8 BOM; net sales integer cocok layar |
| `flutter-test.log` | 134/134 lulus: 53 sebelumnya + 78 layout + 2 interaksi POS + 1 list panjang |
| `flutter-analyze.log` | Analyzer 0 issue |
| `flutter-web-build.log` | Build web release berhasil |
| `android-first-attempt.log` | Kegagalan pertama: DNS download Google Storage |
| `android-build.log`, `android-build.json` | Retry JVM IPv4 menghasilkan APK **unsigned**, checksum/ukuran/scan |
| `public-security.json` | 29 probe hosted publik: tabel privat/RPC internal/token injection ditolak |
| `non-operator-rls.json` | Akun bukan operator ditolak dalam restore staging dengan stub JWT |
| `secret-scan.json` | Scan pola source; tidak menggantikan rotasi password yang dahulu ter-commit |
| `backup-restore.json` | 25 tabel/checksum/total uang dan 23 policy pulih di PostgreSQL lokal |
| `rpc-latency.json` | Lima request/endpoint, termasuk retry/kegagalan transport |
| `retry-gap.json` | **Blocker awal**: partial refund dan koreksi stok identik berlaku dua kali |
| `retry-fix.json` | **Perbaikan K06-01**: migrasi `0013` terpasang di hosted, uji replay dalam `BEGIN/ROLLBACK`, probe anon, 9 tes SQL, 148 tes Flutter, regresi hosted 212 PASS |

Regresi backend Sprint 06: POS **77**, inventori **57**, QR **37**, operasional
**41** = **212 PASS, 0 FAIL** — dijalankan ulang terhadap hosted **setelah**
migrasi `0013` dengan caller yang sudah mengirim `p_idempotency_key`
(`retry-fix.json`). Suite memerlukan `OPERATOR_PASSWORD` environment dan
membuat data uji; jangan dijalankan pada database operasional aktif.

78 layout case = 13 halaman × dua viewport × empty/loading/error (halaman statis
tetap baseline; Pengaturan memakai profil valid). Bukan bukti seluruh modal,
data panjang, aksesibilitas atau keyboard pada Android.
Fixture katalog 1.000 item memverifikasi lazy rendering + scroll; waktu debug
5.227/7.114 ms dari harness lokal bukan ukuran FPS atau profil native.

`graphify update .` selesai (1.152 node, 1.539 edge); tool memperingatkan parser
SQL `tree_sitter_sql` belum terpasang dan sebagian JSON evidence tidak menghasilkan
node. Pembaruan AST bukan pengganti tes SQL atau audit semantik dokumen.

**Gate:** retry `pos_refund`/`inv_adjust_stock` **sudah terpasang dan terbukti**
di hosted (`retry-fix.json`); audit RPC mutasi lain, keystore/signature/instalasi,
tablet target, rotasi password lama, full Supabase Auth/Storage restore, hosting QR
permanen dan persetujuan operator **masih terbuka**. Lihat `../../handover.md`.

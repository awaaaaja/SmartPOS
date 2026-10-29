# E2E (Playwright)

Uji alur browser sungguhan (Chromium headless) untuk web menu pelanggan QR.
**Semua panggilan Supabase di-mocking lewat `page.route`** — test ini tidak
menyentuh database bisnis, tidak butuh `OPERATOR_PASSWORD`, dan aman dijalankan
di mana pun.

## Jalankan

```bash
cd tests/e2e
npm ci
npx playwright install chromium   # sekali saja
npm test
```

Vite dev server di `apps/qr_web` dijalankan otomatis oleh Playwright
(`webServer` di `playwright.config.js`, port 5199) dengan env dummy.

## Cakupan (`qr_customer.spec.js`)

| Skenario | Yang dibuktikan |
|---|---|
| Alur penuh | QR → menu tampil → varian wajib → keranjang → submit → halaman konfirmasi referensi ("Pesanan belum dibayar") → Pesan lagi |
| Token hilang | Halaman jujur "QR tidak valid", tanpa panggilan jaringan |
| Token ditolak server | Pesan minta QR meja terbaru |
| Submit gagal (rate limit) | Pesan manusiawi, keranjang TIDAK dikosongkan, hanya 1 percobaan |

## Batasan

- Menggantikan bukti e2e manual Sprint 02–06 (screenshot Chrome di
  `docs/evidence/`), bukan pengujian perangkat Android — itu tetap manual
  (lihat `docs/handover.md`, blocker K06-03).
- Jalur kasir (Flutter) belum punya e2e otomatis; cakupannya unit/widget test
  di `apps/pos_flutter/test`.

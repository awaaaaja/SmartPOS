// E2E alur pelanggan QR: browser sungguhan (Chromium) terhadap vite dev,
// seluruh panggilan Supabase REST/RPC dimocking via page.route sehingga
// test tidak menyentuh database bisnis.
import { test, expect } from '@playwright/test';

const MENU = {
  table: { id: 1, label: 'Meja 3' },
  categories: [
    {
      id: 1,
      name: 'Minuman',
      products: [
        { id: 10, name: 'Es Teh', price: 5000, modifiers: [] },
        {
          id: 11,
          name: 'Es Campur',
          price: 10000,
          modifiers: [
            { id: 100, name: 'Cincau', price_delta: 2000, min_select: 1,
              max_select: 1 },
          ],
        },
      ],
    },
  ],
};

// Intercept semua panggilan RPC PostgREST; kembalikan payload sesuai nama.
// Handler melempar {message} untuk meniru error PostgREST (status 400).
function mockRpc(page, handlers) {
  return page.route('**/rest/v1/rpc/*', async (route) => {
    const name = route.request().url().split('/').pop();
    const handler = handlers[name];
    if (!handler) {
      return route.fulfill({ status: 404, json: { message: 'not mocked' } });
    }
    try {
      const result = await handler(route.request().postDataJSON() ?? {});
      return route.fulfill({ status: 200, json: result });
    } catch (e) {
      return route.fulfill({ status: 400, json: { message: e?.message ?? String(e) } });
    }
  });
}

test('alur penuh: buka QR -> pesan -> konfirmasi draf', async ({ page }) => {
  await mockRpc(page, {
    get_public_menu: async () => MENU,
    qr_submit_draft: async (params) => {
      // Server menghitung ulang; ini jawaban mock yang konsisten.
      expect(params.p_client_key).toBeTruthy();
      expect(params.p_table_token).toBe('TOKEN-E2E');
      return {
        draft_id: 1,
        ref_code: 'Q00099',
        table_label: 'Meja 3',
        subtotal: 17000,
        item_count: 2,
        idempotent_replay: false,
      };
    },
  });

  await page.goto('/?token=TOKEN-E2E');

  // Logo merek tampil di header dan benar-benar termuat (bukan 404).
  const logo = page.locator('img.brand-logo');
  await expect(logo).toBeVisible();
  expect(await logo.evaluate((el) => el.naturalWidth)).toBeGreaterThan(0);

  // Menu tampil dengan nama meja.
  await expect(page.getByRole('button', { name: /Es Campur/ })).toBeVisible();
  await expect(page.getByText('Meja 3 · Pesan dari meja Anda')).toBeVisible();

  // Pesan Es Campur dengan varian wajib, lalu Es Teh.
  await page.getByRole('button', { name: /Es Campur/ }).click();
  await page.getByLabel(/Cincau/).check();
  await page.getByRole('button', { name: /^Tambah ·/ }).click();
  await page.getByRole('button', { name: /Tutup/ }).click();
  await page.getByRole('button', { name: /Es Teh/ }).click();
  await page.getByRole('button', { name: /^Tambah ·/ }).click();

  // Keranjang: 2 item, Rp 17.000 (sheet terbuka otomatis setelah Tambah).
  await expect(page.getByRole('button', { name: /Keranjang \(2\)/ }))
    .toContainText('Rp 17.000');

  await page.getByRole('button', { name: 'Kirim pesanan ke kasir' }).click();

  // Halaman konfirmasi: referensi ada, tapi JUJUR belum dibayar.
  await expect(page.getByRole('heading', { name: 'Pesanan diterima' }))
    .toBeVisible();
  await expect(page.getByText('Referensi Q00099')).toBeVisible();
  await expect(page.getByText('Pesanan belum dibayar')).toBeVisible();

  // Pesan lagi -> kembali ke menu, key baru untuk draft berikutnya.
  await page.getByRole('button', { name: 'Pesan lagi' }).click();
  await expect(page.getByRole('button', { name: /Es Teh/ })).toBeVisible();
});

test('token tidak ada di tautan -> halaman QR tidak valid (jujur)',
     async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'QR tidak valid' }))
    .toBeVisible();
  await expect(page.getByText('Token meja tidak ditemukan')).toBeVisible();
});

test('token ditolak server -> pesan minta QR terbaru', async ({ page }) => {
  await mockRpc(page, {
    get_public_menu: async () => {
      throw new Error('invalid_table_token');
    },
  });
  await page.goto('/?token=SUDAH-DIROTASI');
  await expect(page.getByRole('heading', { name: 'QR tidak valid' }))
    .toBeVisible();
  await expect(page.getByText('Mintalah QR meja terbaru')).toBeVisible();
});

test('submit gagal (rate limit) -> pesan manusiawi, keranjang utuh',
     async ({ page }) => {
  let submitCalls = 0;
  await mockRpc(page, {
    get_public_menu: async () => MENU,
    qr_submit_draft: async () => {
      submitCalls += 1;
      throw new Error('rate_limited');
    },
  });

  await page.goto('/?token=TOKEN-E2E');
  await page.getByRole('button', { name: /Es Teh/ }).click();
  await page.getByRole('button', { name: /^Tambah ·/ }).click();
  // addToCart membuka sheet keranjang secara otomatis.
  await page.getByRole('button', { name: 'Kirim pesanan ke kasir' }).click();

  await expect(page.getByText('Terlalu sering mengirim pesanan')).toBeVisible();
  // Keranjang tidak dikosongkan saat gagal.
  await expect(page.getByRole('button', { name: 'Kirim pesanan ke kasir' }))
    .toBeEnabled();
  expect(submitCalls).toBe(1);
});

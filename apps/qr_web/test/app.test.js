import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import App from '../src/App.vue';

// Klien Supabase dipalsukan sepenuhnya: tidak ada jaringan, tidak ada env.
const { rpcMock } = vi.hoisted(() => ({ rpcMock: vi.fn() }));
vi.mock('../src/api/supabaseClient.js', () => ({
  supabase: { rpc: (...args) => rpcMock(...args) },
}));

const MENU = {
  table: { id: 1, label: 'Meja 1' },
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
            { id: 101, name: 'Sirup', price_delta: 1000, min_select: 1,
              max_select: 1 },
          ],
        },
      ],
    },
    {
      id: 2,
      name: 'Makanan',
      products: [
        { id: 20, name: 'Nasi Goreng', price: 15000, modifiers: [] },
      ],
    },
  ],
};

function setToken(token) {
  window.history.replaceState({}, '', token === null ? '/' : `/?token=${token}`);
}

async function mountReady(menu = MENU) {
  rpcMock.mockResolvedValueOnce({ data: menu, error: null });
  const wrapper = mount(App);
  await flushPromises();
  return wrapper;
}

/** Lewati langkah 1 (identitas opsional) -> daftar menu tampil. */
async function goToMenu(wrapper) {
  await wrapper.find('button.btn.primary.wide').trigger('click');
  await flushPromises();
}

/** Tambah 1 produk (lewati sheet varian bila ada pilihan wajib). */
async function addFirstProduct(wrapper) {
  await wrapper.findAll('button.product')[0].trigger('click');
  await wrapper.find('button.primary.wide').trigger('click');
}

/** Buka sheet keranjang dari bar bawah lalu Lanjut ke pembayaran. */
async function openCartAndPay(wrapper) {
  await wrapper.find('.cart-bar button').trigger('click');
  await wrapper.find('.sheet button.primary.wide').trigger('click');
  await flushPromises();
}

beforeEach(() => {
  rpcMock.mockReset();
  localStorage.clear();
  setToken('TOKEN-VALID');
});

describe('memuat menu', () => {
  it('menolak tautan tanpa token (jujur, tidak pura-pura)', async () => {
    setToken(null);
    const wrapper = mount(App);
    await flushPromises();
    expect(wrapper.text()).toContain('QR tidak valid');
    expect(wrapper.text()).toContain('Token meja tidak ditemukan');
    expect(rpcMock).not.toHaveBeenCalled();
  });

  it('menampilkan kategori dan produk dari get_public_menu', async () => {
    const wrapper = await mountReady();
    expect(rpcMock).toHaveBeenCalledWith('get_public_menu', {
      p_table_token: 'TOKEN-VALID',
    });
    expect(wrapper.text()).toContain('Meja 1');
    await goToMenu(wrapper);
    expect(wrapper.text()).toContain('Minuman');
    expect(wrapper.text()).toContain('Es Teh');
    expect(wrapper.text()).toContain('Rp 5.000');
  });

  it('memasang logo merek di header (bukan placeholder)', async () => {
    const wrapper = await mountReady();
    const logo = wrapper.find('img.brand-logo');
    expect(logo.exists()).toBe(true);
    expect(logo.attributes('src')).toBe('/logo-mark.png');
  });

  it('memetakan invalid_table_token ke pesan QR tidak valid', async () => {
    rpcMock.mockResolvedValueOnce({
      data: null,
      error: { message: 'invalid_table_token' },
    });
    const wrapper = mount(App);
    await flushPromises();
    expect(wrapper.text()).toContain('QR tidak valid');
    expect(wrapper.text()).toContain('Mintalah QR meja terbaru');
  });

  it('menampilkan kegagalan jaringan sebagai error memuat, dengan Coba lagi',
     async () => {
    rpcMock.mockResolvedValueOnce({ data: null, error: { message: 'boom' } });
    const wrapper = mount(App);
    await flushPromises();
    expect(wrapper.text()).toContain('Gagal memuat menu');
    rpcMock.mockResolvedValueOnce({ data: MENU, error: null });
    await wrapper.find('button.btn.primary').trigger('click');
    await flushPromises();
    await goToMenu(wrapper);
    expect(wrapper.text()).toContain('Es Campur');
  });
});

describe('langkah 1: niat bayar & identitas', () => {
  it('menawarkan dua niat bayar dengan Bayar sekarang sebagai DEFAULT',
     async () => {
    const wrapper = await mountReady();
    const intents = wrapper.findAll('.intent-grid .intent');
    expect(intents).toHaveLength(2);
    expect(intents[0].text()).toContain('Bayar sekarang (ke kasir)');
    expect(intents[1].text()).toContain('Open Bill');
    expect(intents[0].classes()).toContain('active');
    expect(intents[1].classes()).not.toContain('active');
  });

  it('menuju langkah Open Bill saat dipilih, tanpa kartu metode', async () => {
    const wrapper = await mountReady();
    await wrapper.findAll('.intent-grid .intent')[1].trigger('click');
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    expect(wrapper.text()).toContain('Bayar nanti di kasir');
    expect(wrapper.text()).not.toContain('Metode pembayaran');
    expect(wrapper.text()).not.toContain('QRIS');
  });

  it('menolak nama lebih dari 60 karakter dengan pesan di bawah field',
     async () => {
    const wrapper = await mountReady();
    const name = wrapper.findAll('input.input')[0];
    await name.setValue('x'.repeat(61));
    expect(wrapper.text()).toContain('Nama maksimal 60 karakter.');
    expect(wrapper.find('button.btn.primary.wide').attributes('disabled'))
      .toBeDefined();
    await name.setValue('x'.repeat(60));
    expect(wrapper.text()).not.toContain('Nama maksimal');
    expect(wrapper.find('button.btn.primary.wide').attributes('disabled'))
      .toBeUndefined();
  });

  it('menolak No. WA dengan karakter terlarang atau digit di luar 8–20',
     async () => {
    const wrapper = await mountReady();
    const phone = wrapper.findAll('input.input')[1];
    await phone.setValue('0812abc');
    expect(wrapper.text()).toContain('No. WA hanya boleh angka');
    await phone.setValue('0812 345');
    expect(wrapper.text()).toContain('No. WA harus 8–20 digit.');
    await phone.setValue('+62 812-3456-7890');
    expect(wrapper.text()).not.toContain('No. WA harus');
    expect(wrapper.text()).not.toContain('No. WA hanya');
    expect(wrapper.find('button.btn.primary.wide').attributes('disabled'))
      .toBeUndefined();
  });

  it('mengirim identitas hanya saat submit, tidak disimpan di localStorage',
     async () => {
    const wrapper = await mountReady();
    await wrapper.findAll('input.input')[0].setValue('Budi');
    await wrapper.findAll('input.input')[1].setValue('081234567890');
    await goToMenu(wrapper);
    expect(localStorage.getItem('qr_client_key')).toBeTruthy();
    expect(localStorage.length).toBe(1); // hanya draft idempotensi
  });
});

describe('langkah 2: pilih menu & keranjang', () => {
  it('menyaring produk lewat chip kategori (Semua | nama kategori)', async () => {
    const wrapper = await mountReady();
    await goToMenu(wrapper);
    const chips = wrapper.findAll('.chip');
    expect(chips.map((c) => c.text())).toEqual(['Semua', 'Minuman', 'Makanan']);
    expect(wrapper.text()).toContain('Nasi Goreng'); // Semua = tampil
    await chips[1].trigger('click'); // Minuman
    expect(wrapper.text()).toContain('Es Teh');
    expect(wrapper.text()).not.toContain('Nasi Goreng');
    await chips[0].trigger('click'); // Semua lagi
    expect(wrapper.text()).toContain('Nasi Goreng');
  });

  it('memaksa pilihan varian sesuai min/max_select sebelum menambah',
     async () => {
    const wrapper = await mountReady();
    await goToMenu(wrapper);
    await wrapper.findAll('button.product')[1].trigger('click');
    const boxes = wrapper.findAll('input[type="checkbox"]');
    expect(boxes).toHaveLength(2);
    const addBtn = () => wrapper.find('button.primary.wide');
    // min 1+1 = 2: belum lengkap -> tombol tambah terkunci.
    expect(addBtn().attributes('disabled')).toBeDefined();
    await boxes[0].trigger('change'); // Cincau (+Rp 2.000)
    expect(addBtn().attributes('disabled')).toBeDefined();
    await boxes[1].trigger('change'); // Sirup (+Rp 1.000) -> lengkap
    expect(addBtn().attributes('disabled')).toBeUndefined();
    expect(addBtn().text()).toContain('Tambah · Rp 13.000');
  });

  it('menjumlahkan subtotal keranjang termasuk modifier', async () => {
    const wrapper = await mountReady();
    await goToMenu(wrapper);
    // Es Teh (tanpa varian; tombol langsung aktif) lalu qty dinaikkan ke 2
    await addFirstProduct(wrapper);
    // Tutup sheet keranjang yang otomatis terbuka sebelum ubah qty.
    await wrapper.find('button.btn.ghost.wide').trigger('click');
    await wrapper.find('.cart-bar button').trigger('click');
    await wrapper.find('.cart-line .btn.tiny:last-child').trigger('click');
    await wrapper.find('button.btn.ghost.wide').trigger('click');
    // Es Campur + Cincau + Sirup x1
    await wrapper.findAll('button.product')[1].trigger('click');
    for (const box of wrapper.findAll('input[type="checkbox"]')) {
      await box.trigger('change');
    }
    await wrapper.find('button.primary.wide').trigger('click');
    const bar = wrapper.find('.cart-bar button');
    expect(bar.text()).toContain('Keranjang (3)');
    expect(bar.text()).toContain('Rp 23.000'); // 2x5000 + 13000
  });

  it('menghapus baris saat qty turun ke nol', async () => {
    const wrapper = await mountReady();
    await goToMenu(wrapper);
    await addFirstProduct(wrapper);
    await wrapper.find('.cart-bar button').trigger('click');
    await wrapper.find('.cart-line .btn.tiny').trigger('click'); // kurangi
    expect(wrapper.text()).toContain('Keranjang kosong');
    // Keranjang kosong -> tombol Lanjut terkunci, tidak bisa ke pembayaran.
    expect(wrapper.find('.sheet button.primary.wide').attributes('disabled'))
      .toBeDefined();
  });

  it('tombol Lanjut bar terkunci selama keranjang kosong', async () => {
    const wrapper = await mountReady();
    await goToMenu(wrapper);
    expect(wrapper.find('.bar-next').attributes('disabled')).toBeDefined();
    await addFirstProduct(wrapper);
    expect(wrapper.find('.bar-next').attributes('disabled')).toBeUndefined();
  });
});

describe('langkah 3: pembayaran & submit draft', () => {
  const DRAFT = {
    ref_code: 'Q00042', table_label: 'Meja 1', subtotal: 7000, item_count: 1,
  };

  it('mengirim item + preferensi & identitas, lalu merotasi key setelah sukses',
     async () => {
    localStorage.setItem('qr_client_key', 'client-key-tetap-01');
    rpcMock.mockResolvedValueOnce({ data: MENU, error: null });
    const wrapper = mount(App);
    await flushPromises();
    await wrapper.findAll('input.input')[0].setValue('  Budi Santoso  ');
    await wrapper.findAll('input.input')[1].setValue('0812 3456-7890');
    await goToMenu(wrapper);
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    // Pilih metode QRIS (PAY_NOW adalah niat DEFAULT).
    await wrapper.findAll('.method-grid .intent')[1].trigger('click');
    rpcMock.mockResolvedValueOnce({ data: DRAFT, error: null });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();

    expect(rpcMock).toHaveBeenLastCalledWith('qr_submit_draft', {
      p_table_token: 'TOKEN-VALID',
      p_client_key: 'client-key-tetap-01',
      p_items: [{ product_id: 10, qty: 1, modifier_ids: [], note: '' }],
      p_pay_intent: 'PAY_NOW',
      p_pay_method: 'QRIS',
      p_customer_name: 'Budi Santoso',   // di-trim sebelum kirim
      p_customer_phone: '0812 3456-7890',
    });
    // Halaman konfirmasi jujur: referensi, tapi BUKAN pembayaran.
    expect(wrapper.text()).toContain('Pesanan diterima');
    expect(wrapper.text()).toContain('Referensi Q00042');
    expect(wrapper.text()).toContain('Pesanan belum dibayar');
    // Baris metode & identitas tampil di konfirmasi.
    expect(wrapper.text()).toContain('Bayar sekarang · QRIS');
    expect(wrapper.text()).toContain('atas nama Budi Santoso');
    // Key dirotasi hanya setelah sukses: retry berikutnya = draft baru.
    expect(localStorage.getItem('qr_client_key'))
      .not.toBe('client-key-tetap-01');
  });

  it('Open Bill mengirim intent tanpa metode (null)', async () => {
    const wrapper = await mountReady();
    await wrapper.findAll('.intent-grid .intent')[1].trigger('click');
    await goToMenu(wrapper);
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    rpcMock.mockResolvedValueOnce({ data: DRAFT, error: null });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    expect(rpcMock).toHaveBeenLastCalledWith('qr_submit_draft',
      expect.objectContaining({
        p_pay_intent: 'OPEN_BILL',
        p_pay_method: null,
        p_customer_name: null,
        p_customer_phone: null,
      }));
  });

  it('metode yang dipilih tadi tidak terkirim saat pindah ke Open Bill',
     async () => {
    const wrapper = await mountReady();
    await goToMenu(wrapper);
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    await wrapper.findAll('.method-grid .intent')[0].trigger('click'); // Tunai
    // Kembali dua langkah: pembayaran -> pilih menu -> langkah 1.
    await wrapper.find('button.btn.ghost').trigger('click'); // ke pilih menu
    await wrapper.find('button.btn.ghost').trigger('click'); // ke langkah 1
    await wrapper.findAll('.intent-grid .intent')[1].trigger('click'); // OB
    await wrapper.find('button.btn.primary.wide').trigger('click'); // menu
    await openCartAndPay(wrapper);
    rpcMock.mockResolvedValueOnce({ data: DRAFT, error: null });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    expect(rpcMock).toHaveBeenLastCalledWith('qr_submit_draft',
      expect.objectContaining({
        p_pay_intent: 'OPEN_BILL',
        p_pay_method: null,
      }));
  });

  it('mempertahankan client key yang sama saat submit gagal (idempoten)',
     async () => {
    localStorage.setItem('qr_client_key', 'client-key-tetap-02');
    rpcMock.mockResolvedValueOnce({ data: MENU, error: null });
    const wrapper = mount(App);
    await flushPromises();
    await goToMenu(wrapper);
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    rpcMock.mockResolvedValueOnce({
      data: null, error: { message: 'network timeout' },
    });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Gagal mengirim pesanan');
    expect(localStorage.getItem('qr_client_key')).toBe('client-key-tetap-02');
    // Coba lagi memakai key yang sama.
    rpcMock.mockResolvedValueOnce({ data: DRAFT, error: null });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    expect(rpcMock).toHaveBeenLastCalledWith('qr_submit_draft',
      expect.objectContaining({ p_client_key: 'client-key-tetap-02' }));
  });

  it('memetakan rate_limited ke pesan yang manusiawi', async () => {
    const wrapper = await mountReady();
    await goToMenu(wrapper);
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    rpcMock.mockResolvedValueOnce({
      data: null, error: { message: 'rate_limited' },
    });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Terlalu sering mengirim pesanan');
  });

  it('Pesan lagi mengosongkan identitas & kembali ke langkah 1', async () => {
    const wrapper = await mountReady();
    await wrapper.findAll('input.input')[0].setValue('Budi');
    await goToMenu(wrapper);
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    rpcMock.mockResolvedValueOnce({ data: DRAFT, error: null });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    await wrapper.findAll('button.btn.primary').filter(
      (b) => b.text() === 'Pesan lagi')[0].trigger('click');
    await flushPromises();
    // Kembali ke langkah 1, form identitas kosong (privasi).
    expect(wrapper.text()).toContain('Bagaimana Anda ingin bayar?');
    expect(wrapper.findAll('input.input')[0].element.value).toBe('');
    expect(wrapper.findAll('input.input')[1].element.value).toBe('');
    // Niat kembali DEFAULT.
    expect(wrapper.findAll('.intent-grid .intent')[0].classes())
      .toContain('active');
  });
});

// ---------------------------------------------------------------------------
// Mode online (?mode=online) — pesanan tanpa QR meja, tanpa login.
// ---------------------------------------------------------------------------
function setOnline() {
  window.history.replaceState({}, '', '/?mode=online');
}

async function mountOnline(menu = MENU) {
  rpcMock.mockResolvedValueOnce({ data: menu, error: null });
  const wrapper = mount(App);
  await flushPromises();
  return wrapper;
}

/** Isi form data pemesan (mode online: nama, WA, alamat). */
async function fillIdentity(wrapper, {
  name = 'Budi', phone = '081234567890', address = 'Jl. Mawar 7',
} = {}) {
  const inputs = wrapper.findAll('input.input');
  await inputs[0].setValue(name);
  await inputs[1].setValue(phone);
  if (inputs[2]) await inputs[2].setValue(address);
}

describe('mode online (?mode=online)', () => {
  it('tanpa token: menu termuat lewat get_online_menu, bukan halaman invalid',
     async () => {
    setOnline();
    const wrapper = await mountOnline();
    expect(rpcMock).toHaveBeenCalledWith('get_online_menu');
    expect(rpcMock).not.toHaveBeenCalledWith('get_public_menu',
      expect.anything());
    expect(wrapper.text()).toContain('Pesan online');
    expect(wrapper.text()).not.toContain('QR tidak valid');
    await fillIdentity(wrapper);
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Nasi Goreng');
  });

  it('nama & WA wajib; alamat wajib hanya saat COD', async () => {
    setOnline();
    const wrapper = await mountOnline();
    const next = () => wrapper.find('button.btn.primary.wide');
    // Belum ada isi -> terkunci + pesan jujur.
    expect(next().attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('Nama wajib diisi.');
    expect(wrapper.text()).toContain('No. WA wajib diisi.');
    await wrapper.findAll('input.input')[0].setValue('Budi');
    await wrapper.findAll('input.input')[1].setValue('081234567890');
    expect(next().attributes('disabled')).toBeUndefined();
    // Pilih COD -> alamat jadi wajib.
    await wrapper.findAll('.intent-grid .intent')[1].trigger('click');
    expect(wrapper.text()).toContain('Alamat wajib diisi untuk pesanan COD');
    expect(next().attributes('disabled')).toBeDefined();
    await wrapper.findAll('input.input')[2].setValue('Jl. Mawar 7');
    expect(next().attributes('disabled')).toBeUndefined();
  });

  it('dua pilihan bayar: Bayar di tempat (DEFAULT) & COD (diantar)',
     async () => {
    setOnline();
    const wrapper = await mountOnline();
    const intents = wrapper.findAll('.intent-grid .intent');
    expect(intents).toHaveLength(2);
    expect(intents[0].text()).toContain('Bayar di tempat');
    expect(intents[1].text()).toContain('COD (diantar)');
    expect(intents[0].classes()).toContain('active');
    // Mode online TIDAK menawarkan niat bayar QR.
    expect(wrapper.text()).not.toContain('Open Bill');
    expect(wrapper.text()).not.toContain('Bayar sekarang (ke kasir)');
  });

  it('submit memanggil qr_online_submit (tanpa token meja) + konfirmasi jujur',
     async () => {
    setOnline();
    localStorage.setItem('qr_client_key', 'client-key-online-01');
    const wrapper = await mountOnline();
    await fillIdentity(wrapper);
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    rpcMock.mockResolvedValueOnce({
      data: {
        ref_code: 'Q00077', table_label: 'Pesanan Online',
        subtotal: 5000, item_count: 1,
      },
      error: null,
    });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();

    expect(rpcMock).toHaveBeenLastCalledWith('qr_online_submit', {
      p_client_key: 'client-key-online-01',
      p_customer_name: 'Budi',
      p_customer_phone: '081234567890',
      p_customer_address: 'Jl. Mawar 7',
      p_pay_intent: 'AT_PLACE',
      p_items: [{ product_id: 10, qty: 1, modifier_ids: [], note: '' }],
    });
    // Konfirmasi jujur: diterima, tapi BUKAN sudah dibayar.
    expect(wrapper.text()).toContain('Pesanan diterima');
    expect(wrapper.text()).toContain('Referensi Q00077');
    expect(wrapper.text()).toContain('Bayar di tempat');
    expect(wrapper.text()).toContain('belum dibayar');
    expect(wrapper.text()).not.toContain('meja Pesanan Online');
  });

  it('COD terkirim dengan alamat & tampil di konfirmasi', async () => {
    setOnline();
    const wrapper = await mountOnline();
    await fillIdentity(wrapper, { address: 'Jl. Mawar 7' });
    await wrapper.findAll('.intent-grid .intent')[1].trigger('click'); // COD
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    rpcMock.mockResolvedValueOnce({
      data: {
        ref_code: 'Q00078', table_label: 'Pesanan Online',
        subtotal: 5000, item_count: 1,
      },
      error: null,
    });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    expect(rpcMock).toHaveBeenLastCalledWith('qr_online_submit',
      expect.objectContaining({
        p_pay_intent: 'COD',
        p_customer_address: 'Jl. Mawar 7',
      }));
    expect(wrapper.text()).toContain('Diantar ke Jl. Mawar 7');
  });

  it('tawaran "Ingat data saya" default aktif & tersimpan setelah submit',
     async () => {
    setOnline();
    const wrapper = await mountOnline();
    // Checkbox default TERCENTANG (keputusan produk).
    expect(wrapper.find('.remember input').element.checked).toBe(true);
    expect(localStorage.getItem('qr_customer_profile')).toBeNull();
    await fillIdentity(wrapper, {
      name: 'Sari', phone: '081299988877', address: 'Jl. Melati 3',
    });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    rpcMock.mockResolvedValueOnce({
      data: {
        ref_code: 'Q00079', table_label: 'Pesanan Online',
        subtotal: 5000, item_count: 1,
      },
      error: null,
    });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();

    // Tersimpan di perangkat INI saja (localStorage, tanpa login).
    expect(JSON.parse(localStorage.getItem('qr_customer_profile')))
      .toEqual({ name: 'Sari', phone: '081299988877',
                 address: 'Jl. Melati 3' });

    // Kunjungan berikutnya: field terisi otomatis + tombol hapus muncul.
    const again = await mountOnline();
    expect(again.findAll('input.input')[0].element.value).toBe('Sari');
    expect(again.findAll('input.input')[1].element.value)
      .toBe('081299988877');
    expect(again.findAll('input.input')[2].element.value)
      .toBe('Jl. Melati 3');
    const clear = again.findAll('button.btn.ghost')
      .find((b) => b.text() === 'Hapus data tersimpan');
    expect(clear).toBeTruthy();
    await clear.trigger('click');
    expect(localStorage.getItem('qr_customer_profile')).toBeNull();
    expect(again.findAll('input.input')[0].element.value).toBe('');
  });

  it('bila centang dilepas, data TIDAK disimpan di perangkat', async () => {
    setOnline();
    const wrapper = await mountOnline();
    await wrapper.find('.remember input').setValue(false);
    expect(wrapper.find('.remember input').element.checked).toBe(false);
    await fillIdentity(wrapper);
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    await addFirstProduct(wrapper);
    await openCartAndPay(wrapper);
    rpcMock.mockResolvedValueOnce({
      data: {
        ref_code: 'Q00080', table_label: 'Pesanan Online',
        subtotal: 5000, item_count: 1,
      },
      error: null,
    });
    await wrapper.find('button.btn.primary.wide').trigger('click');
    await flushPromises();
    expect(localStorage.getItem('qr_customer_profile')).toBeNull();
  });
});

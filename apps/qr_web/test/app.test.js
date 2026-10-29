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
    expect(wrapper.text()).toContain('Minuman');
    expect(wrapper.text()).toContain('Es Teh');
    expect(wrapper.text()).toContain('Rp 5.000');
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
    expect(wrapper.text()).toContain('Es Campur');
  });
});

describe('varian dan keranjang', () => {
  it('memaksa pilihan varian sesuai min/max_select sebelum menambah',
     async () => {
    const wrapper = await mountReady();
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
    // Es Teh (tanpa varian; tombol langsung aktif) lalu qty dinaikkan ke 2
    await wrapper.findAll('button.product')[0].trigger('click');
    await wrapper.find('button.primary.wide').trigger('click');
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
    await wrapper.findAll('button.product')[0].trigger('click');
    await wrapper.find('button.primary.wide').trigger('click');
    await wrapper.find('.cart-bar button').trigger('click');
    await wrapper.find('.cart-line .btn.tiny').trigger('click'); // kurangi
    expect(wrapper.text()).toContain('Keranjang kosong');
  });
});

describe('submit draft', () => {
  const DRAFT = {
    ref_code: 'Q00042', table_label: 'Meja 1', subtotal: 7000, item_count: 1,
  };

  it('mengirim item dengan client key lalu merotasi key setelah sukses',
     async () => {
    localStorage.setItem('qr_client_key', 'client-key-tetap-01');
    rpcMock.mockResolvedValueOnce({ data: MENU, error: null });
    const wrapper = mount(App);
    await flushPromises();
    await wrapper.findAll('button.product')[0].trigger('click');
    await wrapper.find('button.primary.wide').trigger('click');
    await wrapper.find('.cart-bar button').trigger('click');
    rpcMock.mockResolvedValueOnce({ data: DRAFT, error: null });
    await wrapper.find('button.primary.wide').trigger('click');
    await flushPromises();

    expect(rpcMock).toHaveBeenLastCalledWith('qr_submit_draft', {
      p_table_token: 'TOKEN-VALID',
      p_client_key: 'client-key-tetap-01',
      p_items: [{ product_id: 10, qty: 1, modifier_ids: [], note: '' }],
    });
    // Halaman konfirmasi jujur: referensi, tapi BUKAN pembayaran.
    expect(wrapper.text()).toContain('Pesanan diterima');
    expect(wrapper.text()).toContain('Referensi Q00042');
    expect(wrapper.text()).toContain('Pesanan belum dibayar');
    // Key dirotasi hanya setelah sukses: retry berikutnya = draft baru.
    expect(localStorage.getItem('qr_client_key'))
      .not.toBe('client-key-tetap-01');
  });

  it('mempertahankan client key yang sama saat submit gagal (idempoten)',
     async () => {
    localStorage.setItem('qr_client_key', 'client-key-tetap-02');
    rpcMock.mockResolvedValueOnce({ data: MENU, error: null });
    const wrapper = mount(App);
    await flushPromises();
    await wrapper.findAll('button.product')[0].trigger('click');
    await wrapper.find('button.primary.wide').trigger('click');
    await wrapper.find('.cart-bar button').trigger('click');
    rpcMock.mockResolvedValueOnce({
      data: null, error: { message: 'network timeout' },
    });
    await wrapper.find('button.primary.wide').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Gagal mengirim pesanan');
    expect(localStorage.getItem('qr_client_key')).toBe('client-key-tetap-02');
    // Coba lagi memakai key yang sama.
    rpcMock.mockResolvedValueOnce({ data: DRAFT, error: null });
    await wrapper.find('button.primary.wide').trigger('click');
    await flushPromises();
    expect(rpcMock).toHaveBeenLastCalledWith('qr_submit_draft',
      expect.objectContaining({ p_client_key: 'client-key-tetap-02' }));
  });

  it('memetakan rate_limited ke pesan yang manusiawi', async () => {
    rpcMock.mockResolvedValueOnce({ data: MENU, error: null });
    const wrapper = mount(App);
    await flushPromises();
    await wrapper.findAll('button.product')[0].trigger('click');
    await wrapper.find('button.primary.wide').trigger('click');
    await wrapper.find('.cart-bar button').trigger('click');
    rpcMock.mockResolvedValueOnce({
      data: null, error: { message: 'rate_limited' },
    });
    await wrapper.find('button.primary.wide').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Terlalu sering mengirim pesanan');
  });
});

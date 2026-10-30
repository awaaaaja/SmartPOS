<script setup>
import { ref, computed, onMounted } from 'vue';
import { supabase } from './api/supabaseClient.js';

const token = ref(new URLSearchParams(location.search).get('token') || '');
const categories = ref([]);
const table = ref(null);
const status = ref('idle'); // idle | loading | ready | invalid | error
const errorMessage = ref('');

// --- Keranjang: [{productId, name, basePrice, qty, note, modifierIds, modifiers}]
const cart = ref([]);
const cartOpen = ref(false);

// --- Sheet varian/qty per produk
const sheetProduct = ref(null);
const sheetQty = ref(1);
const sheetNote = ref('');
const sheetSelected = ref([]);

// --- Submit draft
const submitting = ref(false);
const submitError = ref('');
// State halaman sukses: { refCode, tableLabel, subtotal, itemCount }
const confirmation = ref(null);

// Idempotensi: satu key dipakai ulang selama retry submit yang sama.
let clientKey = localStorage.getItem('qr_client_key');
if (!clientKey) {
  clientKey = crypto.randomUUID();
  localStorage.setItem('qr_client_key', clientKey);
}

function newClientKey() {
  // Dipanggil SETELAH draft berhasil dikirim, agar pesanan berikutnya
  // (dan retry setelah sukses) memakai identitas baru.
  clientKey = crypto.randomUUID();
  localStorage.setItem('qr_client_key', clientKey);
}

const cartCount = computed(() => cart.value.reduce((n, l) => n + l.qty, 0));
const cartSubtotal = computed(() =>
  cart.value.reduce((sum, l) => {
    const delta = l.modifiers.reduce((s, m) => s + m.price_delta, 0);
    return sum + (l.basePrice + delta) * l.qty;
  }, 0)
);

function rupiah(n) {
  return 'Rp ' + Number(n).toLocaleString('id-ID');
}

function openSheet(p) {
  sheetProduct.value = p;
  sheetQty.value = 1;
  sheetNote.value = '';
  sheetSelected.value = [];
}

function minRequired(p) {
  return (p.modifiers || []).reduce((s, m) => s + (m.min_select || 0), 0);
}
function maxAllowed(p) {
  return (p.modifiers || []).reduce((s, m) => s + (m.max_select || 0), 0);
}
function toggleModifier(m) {
  const i = sheetSelected.value.indexOf(m.id);
  if (i >= 0) {
    sheetSelected.value.splice(i, 1);
  } else if (sheetSelected.value.length < maxAllowed(sheetProduct.value)) {
    sheetSelected.value.push(m.id);
  }
}

const sheetUnit = computed(() => {
  const p = sheetProduct.value;
  if (!p) return 0;
  const delta = (p.modifiers || [])
    .filter((m) => sheetSelected.value.includes(m.id))
    .reduce((s, m) => s + m.price_delta, 0);
  return p.price + delta;
});

const sheetValid = computed(() => {
  const p = sheetProduct.value;
  if (!p) return false;
  const n = sheetSelected.value.length;
  return n >= minRequired(p) && n <= maxAllowed(p);
});

function addToCart() {
  const p = sheetProduct.value;
  const mods = (p.modifiers || [])
    .filter((m) => sheetSelected.value.includes(m.id))
    .map((m) => ({ id: m.id, name: m.name, price_delta: m.price_delta }));
  cart.value.push({
    productId: p.id,
    name: p.name,
    basePrice: p.price,
    qty: sheetQty.value,
    note: sheetNote.value.trim(),
    modifierIds: [...sheetSelected.value],
    modifiers: mods,
  });
  sheetProduct.value = null;
  cartOpen.value = true;
}

function changeQty(i, d) {
  const line = cart.value[i];
  line.qty += d;
  if (line.qty <= 0) cart.value.splice(i, 1);
}

async function submitDraft() {
  if (submitting.value || cart.value.length === 0) return;
  submitting.value = true;
  submitError.value = '';
  try {
    const items = cart.value.map((l) => ({
      product_id: l.productId,
      qty: l.qty,
      modifier_ids: l.modifierIds,
      note: l.note,
    }));
    const { data, error } = await supabase.rpc('qr_submit_draft', {
      p_table_token: token.value.trim(),
      p_client_key: clientKey,
      p_items: items,
    });
    if (error) throw error;
    confirmation.value = {
      refCode: data.ref_code,
      tableLabel: data.table_label,
      subtotal: data.subtotal,
      itemCount: data.item_count,
    };
    cart.value = [];
    cartOpen.value = false;
    newClientKey(); // pesanan berikutnya = draft baru
  } catch (e) {
    const msg = String(e?.message || e);
    if (msg.includes('rate_limited')) {
      submitError.value =
        'Terlalu sering mengirim pesanan. Tunggu beberapa menit lalu coba lagi.';
    } else if (msg.includes('invalid_table_token')) {
      submitError.value =
        'QR tidak valid atau sudah diganti. Mintalah QR meja terbaru ke kasir.';
    } else if (msg.includes('product_unavailable')) {
      submitError.value =
        'Ada menu yang sudah tidak tersedia. Perbarui keranjang Anda.';
    } else {
      submitError.value = 'Gagal mengirim pesanan. Coba lagi.';
    }
  } finally {
    submitting.value = false;
  }
}

function orderAgain() {
  confirmation.value = null;
}

async function loadMenu() {
  const t = token.value.trim();
  if (!t) {
    status.value = 'invalid';
    errorMessage.value =
      'Token meja tidak ditemukan di tautan. Mintalah QR meja yang benar ke kasir.';
    return;
  }
  status.value = 'loading';
  errorMessage.value = '';
  try {
    const { data, error } = await supabase.rpc('get_public_menu', {
      p_table_token: t,
    });
    if (error) throw error;
    categories.value = data?.categories ?? [];
    table.value = data?.table ?? null;
    status.value = 'ready';
  } catch (e) {
    const msg = String(e?.message || e);
    if (msg.includes('invalid_table_token')) {
      status.value = 'invalid';
      errorMessage.value =
        'QR tidak valid atau sudah diganti. Mintalah QR meja terbaru ke kasir.';
    } else {
      status.value = 'error';
      errorMessage.value =
        'Gagal memuat menu. Periksa koneksi lalu muat ulang halaman.';
    }
  }
}

onMounted(loadMenu);
</script>

<template>
  <header class="app-header">
    <img
      class="brand-logo"
      src="/logo-mark.png"
      alt=""
      width="46"
      height="46"
      aria-hidden="true"
    />
    <div class="brand-text">
      <h1>Waroeng MeJeng Kampoeng</h1>
      <p v-if="table">{{ table.label }} · Pesan dari meja Anda</p>
      <p v-else>Menu pelanggan</p>
    </div>
  </header>

  <main class="content">
    <!-- Halaman konfirmasi referensi (draft terkirim; BUKAN pembayaran) -->
    <div v-if="confirmation" class="card confirm">
      <svg class="confirm-icon" viewBox="0 0 24 24" width="44" height="44"
           fill="none" stroke="#187449" stroke-width="2.5"
           stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <polyline points="20 6 9 17 4 12" />
      </svg>
      <h2>Pesanan diterima</h2>
      <p class="confirm-ref">Referensi {{ confirmation.refCode }}</p>
      <p>
        {{ confirmation.itemCount }} item ·
        {{ rupiah(confirmation.subtotal) }} · meja
        {{ confirmation.tableLabel }}
      </p>
      <p class="confirm-note">
        Tunjukkan referensi ini ke kasir untuk konfirmasi dan pembayaran.
        Pesanan belum dibayar.
      </p>
      <button class="btn primary" @click="orderAgain">Pesan lagi</button>
    </div>

    <div v-else-if="status === 'invalid'" class="card center">
      <h2>QR tidak valid</h2>
      <p class="muted">{{ errorMessage }}</p>
    </div>

    <div v-else-if="status === 'error'" class="card center">
      <h2>Gagal memuat</h2>
      <p class="muted">{{ errorMessage }}</p>
      <button class="btn primary" @click="loadMenu">Coba lagi</button>
    </div>

    <div v-else-if="status === 'loading'" class="card center">
      <p class="muted">Memuat menu…</p>
    </div>

    <template v-else>
      <section v-for="c in categories" :key="c.id" class="cat">
        <h2 class="cat-title">{{ c.name }}</h2>
        <div class="grid">
          <button
            v-for="p in c.products"
            :key="p.id"
            class="card product"
            @click="openSheet(p)"
          >
            <span class="p-name">{{ p.name }}</span>
            <span class="p-price">{{ rupiah(p.price) }}</span>
            <span v-if="(p.modifiers || []).length" class="p-var">
              Ada pilihan
            </span>
          </button>
        </div>
      </section>
      <p v-if="categories.length === 0" class="muted center">
        Menu belum tersedia.
      </p>
    </template>
  </main>

  <!-- Bar keranjang -->
  <footer v-if="status === 'ready' && !confirmation" class="cart-bar">
    <button class="btn ghost" @click="cartOpen = true">
      Keranjang ({{ cartCount }}) · {{ rupiah(cartSubtotal) }}
    </button>
  </footer>

  <!-- Sheet keranjang -->
  <div v-if="cartOpen" class="sheet-backdrop" @click.self="cartOpen = false">
    <div class="sheet">
      <h2>Keranjang</h2>
      <div v-if="cart.length === 0" class="muted center">
        Keranjang kosong.
      </div>
      <ul class="cart-list">
        <li v-for="(l, i) in cart" :key="i" class="cart-line">
          <div class="line-main">
            <span class="p-name">{{ l.name }}</span>
            <span class="muted" v-if="l.modifiers.length">
              {{ l.modifiers.map((m) => m.name).join(', ') }}
            </span>
            <span class="muted" v-if="l.note">Catatan: {{ l.note }}</span>
          </div>
          <div class="line-side">
            <span>{{ rupiah((l.basePrice + l.modifiers.reduce((s, m) => s + m.price_delta, 0)) * l.qty) }}</span>
            <span class="qty">
              <button class="btn tiny" @click="changeQty(i, -1)">−</button>
              {{ l.qty }}
              <button class="btn tiny" @click="changeQty(i, 1)">+</button>
            </span>
          </div>
        </li>
      </ul>
      <p v-if="submitError" class="error">{{ submitError }}</p>
      <button
        class="btn primary wide"
        :disabled="submitting || cart.length === 0"
        @click="submitDraft"
      >
        {{ submitting ? 'Mengirim…' : 'Kirim pesanan ke kasir' }}
      </button>
      <p class="muted small">
        Pesanan dikirim sebagai draf; kasir akan memanggil Anda untuk
        konfirmasi dan pembayaran.
      </p>
      <button class="btn ghost wide" @click="cartOpen = false">Tutup</button>
    </div>
  </div>

  <!-- Sheet varian / qty -->
  <div v-if="sheetProduct" class="sheet-backdrop" @click.self="sheetProduct = null">
    <div class="sheet">
      <h2>{{ sheetProduct.name }}</h2>
      <p class="muted">{{ rupiah(sheetProduct.price) }}</p>
      <label
        v-for="m in sheetProduct.modifiers || []"
        :key="m.id"
        class="mod-row"
      >
        <input
          type="checkbox"
          :checked="sheetSelected.includes(m.id)"
          @change="toggleModifier(m)"
        />
        {{ m.name }} (+{{ rupiah(m.price_delta) }})
        <span v-if="m.min_select > 0" class="muted small">
          min {{ m.min_select }}
        </span>
      </label>
      <p v-if="!sheetValid" class="error small">
        Pilih minimal {{ minRequired(sheetProduct) }} dan maksimal
        {{ maxAllowed(sheetProduct) }} tambahan.
      </p>
      <input
        v-model="sheetNote"
        class="input"
        placeholder="Catatan (opsional)"
        maxlength="120"
      />
      <div class="qty-row">
        <button class="btn tiny" :disabled="sheetQty <= 1" @click="sheetQty--">−</button>
        <span>{{ sheetQty }}</span>
        <button class="btn tiny" @click="sheetQty++">+</button>
      </div>
      <button class="btn primary wide" :disabled="!sheetValid" @click="addToCart">
        Tambah · {{ rupiah(sheetUnit * sheetQty) }}
      </button>
    </div>
  </div>
</template>

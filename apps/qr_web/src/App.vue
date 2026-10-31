<script setup>
import { ref, computed, onMounted } from 'vue';
import { supabase } from './api/supabaseClient.js';

const token = ref(new URLSearchParams(location.search).get('token') || '');
const categories = ref([]);
const table = ref(null);
const status = ref('idle'); // idle | loading | ready | invalid | error
const errorMessage = ref('');

// --- Wizard 3 langkah (tanpa router; ramah GitHub Pages base /SmartPOS/)
// 1 MULAI (niat bayar + identitas opsional) · 2 PILIH MENU · 3 PEMBAYARAN
const step = ref(1);

// --- Niat bayar & identitas pelanggan (opsional; dikirim saat submit saja)
const PAY_NOW = 'PAY_NOW';
const OPEN_BILL = 'OPEN_BILL';
const payIntent = ref(PAY_NOW); // DEFAULT: bayar sekarang (ke kasir)
const payMethod = ref(null);    // CASH | QRIS | TRANSFER (hanya PAY_NOW)
const METHODS = [
  { id: 'CASH', name: 'Tunai', hint: 'Bayar tunai di kasir' },
  { id: 'QRIS', name: 'QRIS', hint: 'Scan kode QRIS di kasir' },
  { id: 'TRANSFER', name: 'Transfer', hint: 'Transfer bank / e-wallet' },
];
const customerName = ref('');
const customerPhone = ref('');
const selectedCategory = ref('all'); // 'all' | id kategori

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
// State halaman sukses: { refCode, tableLabel, subtotal, itemCount,
//                         payIntent, payMethod, customerName }
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

// --- Validasi identitas (ringan, jujur): kosong selalu boleh.
const nameError = computed(() =>
  customerName.value.trim().length > 60 ? 'Nama maksimal 60 karakter.' : ''
);
const phoneError = computed(() => {
  const raw = customerPhone.value.trim();
  if (!raw) return '';
  if (!/^[0-9+\- ]+$/.test(raw)) {
    return 'No. WA hanya boleh angka, +, - dan spasi.';
  }
  const digits = raw.replace(/\D/g, '').length;
  if (digits < 8 || digits > 20) return 'No. WA harus 8–20 digit.';
  return '';
});
const identityValid = computed(() => !nameError.value && !phoneError.value);

// --- Navigasi langkah
function goMenu() {
  if (!identityValid.value) return;
  step.value = 2;
}
function goPay() {
  if (cart.value.length === 0 || !identityValid.value) return;
  cartOpen.value = false;
  step.value = 3;
}
function goBack() {
  step.value = step.value === 3 ? 2 : 1;
}

function toggleMethod(id) {
  payMethod.value = payMethod.value === id ? null : id;
}

const visibleCategories = computed(() =>
  selectedCategory.value === 'all'
    ? categories.value
    : categories.value.filter((c) => c.id === selectedCategory.value)
);

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

function lineTotal(l) {
  const delta = l.modifiers.reduce((s, m) => s + m.price_delta, 0);
  return (l.basePrice + delta) * l.qty;
}

async function submitDraft() {
  if (submitting.value || cart.value.length === 0 || !identityValid.value) {
    return;
  }
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
      p_pay_intent: payIntent.value,
      // Metode hanya bermakna saat bayar sekarang (validasi server 0018).
      p_pay_method: payIntent.value === PAY_NOW ? payMethod.value : null,
      // Nama/No. WA hanya meta penagihan; tidak disimpan di localStorage.
      p_customer_name: customerName.value.trim() || null,
      p_customer_phone: customerPhone.value.trim() || null,
    });
    if (error) throw error;
    confirmation.value = {
      refCode: data.ref_code,
      tableLabel: data.table_label,
      subtotal: data.subtotal,
      itemCount: data.item_count,
      payIntent: payIntent.value,
      payMethod: payIntent.value === PAY_NOW ? payMethod.value : null,
      customerName: customerName.value.trim(),
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
  // Privasi: identitas & pilihan kosong kembali — tidak menempel di
  // perangkat berikutnya. Client key sudah dirotasi saat submit sukses.
  confirmation.value = null;
  step.value = 1;
  payIntent.value = PAY_NOW;
  payMethod.value = null;
  customerName.value = '';
  customerPhone.value = '';
  selectedCategory.value = 'all';
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
    <!-- Indikator langkah (hanya saat memesan) -->
    <nav v-if="status === 'ready' && !confirmation" class="steps"
         aria-label="Langkah pesanan">
      <span class="step" :class="{ on: step === 1 }">1 Mulai</span>
      <span class="step" :class="{ on: step === 2 }">2 Pilih menu</span>
      <span class="step" :class="{ on: step === 3 }">3 Pembayaran</span>
    </nav>

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
      <p class="confirm-meta">
        {{ confirmation.payIntent === 'PAY_NOW' ? 'Bayar sekarang' : 'Open Bill' }}<template
          v-if="confirmation.payMethod"> · {{ confirmation.payMethod }}</template>
        <template v-if="confirmation.customerName"> · atas nama
          {{ confirmation.customerName }}</template>
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
      <!-- Langkah 1: niat bayar + identitas opsional -->
      <section v-if="step === 1">
        <h2 class="cat-title">Bagaimana Anda ingin bayar?</h2>
        <div class="intent-grid">
          <button
            class="intent"
            :class="{ active: payIntent === 'PAY_NOW' }"
            :aria-pressed="payIntent === 'PAY_NOW'"
            @click="payIntent = 'PAY_NOW'"
          >
            <strong>Bayar sekarang (ke kasir)</strong>
            <span class="muted small">
              Pesanan dikirim ke kasir; siapkan pembayaran.
            </span>
          </button>
          <button
            class="intent"
            :class="{ active: payIntent === 'OPEN_BILL' }"
            :aria-pressed="payIntent === 'OPEN_BILL'"
            @click="payIntent = 'OPEN_BILL'"
          >
            <strong>Open Bill</strong>
            <span class="muted small">
              Pesan dulu, bayar nanti di kasir.
            </span>
          </button>
        </div>

        <div class="card">
          <h3 class="pay-h">Identitas (opsional)</h3>
          <p class="muted small">
            Untuk kasir menghubungi Anda bila perlu; tidak disimpan di
            perangkat ini.
          </p>
          <input
            v-model="customerName"
            class="input"
            :class="{ bad: nameError }"
            placeholder="Nama (opsional)"
            maxlength="120"
          />
          <p v-if="nameError" class="error small">{{ nameError }}</p>
          <input
            v-model="customerPhone"
            class="input"
            :class="{ bad: phoneError }"
            placeholder="No. WA (opsional)"
            inputmode="tel"
            maxlength="40"
          />
          <p v-if="phoneError" class="error small">{{ phoneError }}</p>
          <button
            class="btn primary wide"
            :disabled="!identityValid"
            @click="goMenu"
          >
            Lanjut pilih menu
          </button>
        </div>
      </section>

      <!-- Langkah 2: pilih menu -->
      <section v-else-if="step === 2">
        <div v-if="categories.length" class="chips" role="tablist"
             aria-label="Kategori menu">
          <button
            class="chip"
            :class="{ active: selectedCategory === 'all' }"
            @click="selectedCategory = 'all'"
          >
            Semua
          </button>
          <button
            v-for="c in categories"
            :key="c.id"
            class="chip"
            :class="{ active: selectedCategory === c.id }"
            @click="selectedCategory = c.id"
          >
            {{ c.name }}
          </button>
        </div>

        <section v-for="c in visibleCategories" :key="c.id" class="cat">
          <h2 class="cat-title">{{ c.name }}</h2>
          <div class="grid">
            <button
              v-for="p in c.products"
              :key="p.id"
              class="card product"
              @click="openSheet(p)"
            >
              <img
                v-if="p.photo_url"
                class="p-photo"
                :src="p.photo_url"
                :alt="p.name"
                loading="lazy"
                width="150"
                height="100"
              />
              <span class="p-name">{{ p.name }}</span>
              <span class="p-price">{{ rupiah(p.price) }}</span>
              <span v-if="(p.modifiers || []).length" class="p-var">
                Ada pilihan
              </span>
            </button>
          </div>
        </section>
        <p v-if="visibleCategories.length === 0" class="muted center">
          Menu belum tersedia.
        </p>
        <button class="btn ghost" @click="goBack">Kembali</button>
      </section>

      <!-- Langkah 3: pembayaran & kirim -->
      <section v-else>
        <h2 class="cat-title">Pembayaran</h2>

        <div class="card">
          <h3 class="pay-h">Ringkasan pesanan</h3>
          <ul class="cart-list">
            <li v-for="(l, i) in cart" :key="i" class="cart-line">
              <div class="line-main">
                <span class="p-name">
                  {{ l.name }}<span class="muted"> ×{{ l.qty }}</span>
                </span>
                <span class="muted" v-if="l.modifiers.length">
                  {{ l.modifiers.map((m) => m.name).join(', ') }}
                </span>
                <span class="muted" v-if="l.note">Catatan: {{ l.note }}</span>
              </div>
              <div class="line-side">
                <span>{{ rupiah(lineTotal(l)) }}</span>
              </div>
            </li>
          </ul>
          <p v-if="cart.length === 0" class="muted center">
            Keranjang kosong.
          </p>
          <p class="summary-line">
            <strong>{{ cartCount }} item · {{ rupiah(cartSubtotal) }}</strong>
          </p>
        </div>

        <div v-if="payIntent === 'PAY_NOW'" class="card">
          <h3 class="pay-h">Metode pembayaran (opsional)</h3>
          <div class="method-grid">
            <button
              v-for="m in METHODS"
              :key="m.id"
              class="intent method"
              :class="{ active: payMethod === m.id }"
              :aria-pressed="payMethod === m.id"
              @click="toggleMethod(m.id)"
            >
              <strong>{{ m.name }}</strong>
              <span class="muted small">{{ m.hint }}</span>
            </button>
          </div>
        </div>
        <div v-else class="card center">
          <p class="pay-h">Bayar nanti di kasir</p>
          <p class="muted small">
            Kasir menyimpan pesanan Anda; bayar saat selesai menyantap.
          </p>
        </div>

        <div v-if="customerName.trim() || customerPhone.trim()" class="card">
          <h3 class="pay-h">Pesanan Anda</h3>
          <p v-if="customerName.trim()">
            Pesanan atas nama {{ customerName.trim() }}
          </p>
          <p v-if="customerPhone.trim()" class="muted small">
            No. WA {{ customerPhone.trim() }} — untuk dihubungi kasir.
          </p>
        </div>

        <p v-if="submitError" class="error">{{ submitError }}</p>
        <button
          class="btn primary wide"
          :disabled="submitting || cart.length === 0 || !identityValid"
          @click="submitDraft"
        >
          {{ submitting ? 'Mengirim…' : 'Kirim pesanan ke kasir' }}
        </button>
        <p class="muted small">
          Pesanan dikirim sebagai draf; kasir akan memanggil Anda untuk
          konfirmasi dan pembayaran.
        </p>
        <button class="btn ghost" @click="goBack">Kembali ke menu</button>
      </section>
    </template>
  </main>

  <!-- Bar keranjang (langkah pilih menu) -->
  <footer
    v-if="status === 'ready' && !confirmation && step === 2"
    class="cart-bar"
  >
    <div class="bar-row">
      <button class="btn ghost" @click="cartOpen = true">
        Keranjang ({{ cartCount }}) · {{ rupiah(cartSubtotal) }}
      </button>
      <button
        class="btn primary bar-next"
        :disabled="cart.length === 0"
        @click="goPay"
      >
        Lanjut
      </button>
    </div>
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
            <span>{{ rupiah(lineTotal(l)) }}</span>
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
        :disabled="cart.length === 0"
        @click="goPay"
      >
        Lanjut
      </button>
      <p class="muted small">
        Lanjut ke pembayaran; Anda masih bisa menambah menu sebelum kirim.
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

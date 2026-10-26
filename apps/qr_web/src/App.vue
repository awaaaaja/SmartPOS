<script setup>
import { ref, onMounted } from 'vue';
import { supabase } from './api/supabaseClient.js';

const token = ref(new URLSearchParams(location.search).get('token') || '');
const menu = ref(null);
const table = ref(null);
const status = ref('idle'); // idle | loading | ready | invalid | error
const errorMessage = ref('');

async function loadMenu() {
  const t = token.value.trim();
  if (!t) {
    status.value = 'invalid';
    errorMessage.value = 'Token meja tidak ditemukan di tautan. Mintalah QR meja yang benar ke kasir.';
    return;
  }
  status.value = 'loading';
  errorMessage.value = '';
  try {
    const { data, error } = await supabase.rpc('get_public_menu', {
      p_table_token: t,
    });
    if (error) throw error;
    menu.value = data?.categories ?? [];
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
      errorMessage.value = 'Gagal memuat menu. Periksa koneksi lalu coba lagi.';
    }
  }
}

onMounted(() => {
  if (token.value) loadMenu();
});
</script>

<template>
  <header class="app-header">
    <h1>Waroeng MeJeng Kampoeng</h1>
    <p v-if="table">Pesanan meja: {{ table.label }}</p>
    <p v-else>Menu pesan mandiri</p>
  </header>

  <main class="content">
    <section v-if="status === 'idle' || status === 'invalid'" class="card token-form">
      <p style="margin-top: 0; color: var(--muted)">
        Buka menu lewat QR meja. Jika tautan tidak membawa token, tempel token di bawah ini.
      </p>
      <input v-model="token" type="text" placeholder="Token meja" autocomplete="off" />
      <button type="button" :disabled="!token.trim()" @click="loadMenu">Buka Menu</button>
      <p v-if="status === 'invalid'" class="state error" style="padding: 16px 0 0">
        {{ errorMessage }}
      </p>
    </section>

    <p v-else-if="status === 'loading'" class="state">Memuat menu…</p>

    <p v-else-if="status === 'error'" class="state error">
      {{ errorMessage }}
      <br /><br />
      <button type="button" class="token-form" style="all: unset" @click="loadMenu">Coba lagi</button>
    </p>

    <template v-else>
      <section v-if="menu.length === 0" class="state">
        Menu belum tersedia. Silakan tanya kasir.
      </section>
      <section v-for="cat in menu" :key="cat.id">
        <h2 class="category-title">{{ cat.name.replace('[DEMO] ', '') }}</h2>
        <div class="card">
          <div v-for="p in cat.products" :key="p.id" class="product-row">
            <span>{{ p.name.replace('[DEMO] ', '') }}</span>
            <span class="price">Rp {{ Number(p.price).toLocaleString('id-ID') }}</span>
          </div>
        </div>
      </section>
    </template>
  </main>
</template>

import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!url || !key) {
  throw new Error(
    'Konfigurasi Supabase belum lengkap. Salin .env.example menjadi .env.local lalu isi VITE_SUPABASE_URL dan VITE_SUPABASE_PUBLISHABLE_KEY.',
  );
}

// Klien publik pelanggan: tanpa login, tanpa secret server.
export const supabase = createClient(url, key);

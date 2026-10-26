-- seed_dev.sql
-- FIXTURE HANYA UNTUK DEVELOPMENT/STAGING. Semua record berlabel [DEMO].
-- Jangan jalankan di produksi; produksi diisi operator melalui aplikasi.
-- Catatan: operator_email di lingkungan dev/staging harus disamakan dengan
-- email akun Supabase Auth operator (lihat README bagian setup).

insert into public.business_settings (id, name, address, operator_email)
values (1, 'Waroeng MeJeng Kampoeng', 'Kalumbuk, Kuranji, Padang',
        'operator@mejeng.id')
on conflict (id) do nothing;

insert into public.product_categories (name, sort_order) values
  ('[DEMO] Makanan', 1),
  ('[DEMO] Camilan', 2),
  ('[DEMO] Minuman', 3)
on conflict (name) do nothing;

insert into public.products (category_id, name, price)
select c.id, v.name, v.price
from (values
  ('[DEMO] Ayam Kremes', 18000, '[DEMO] Makanan'),
  ('[DEMO] Mie Tarempa', 22000, '[DEMO] Makanan'),
  ('[DEMO] Seblak / Mie', 16000, '[DEMO] Makanan'),
  ('[DEMO] Nasi Goreng', 18000, '[DEMO] Makanan'),
  ('[DEMO] Corndog', 12000, '[DEMO] Camilan'),
  ('[DEMO] Risol', 5000, '[DEMO] Camilan'),
  ('[DEMO] Jagung Pedas', 10000, '[DEMO] Camilan'),
  ('[DEMO] Teh Es/Panas', 6000, '[DEMO] Minuman'),
  ('[DEMO] Teh Hijau', 7000, '[DEMO] Minuman'),
  ('[DEMO] Sekoteng', 12000, '[DEMO] Minuman')
) as v(name, price, cat)
join public.product_categories c on c.name = v.cat
on conflict do nothing;

-- Token meja DEV saja: ganti/rotasi sebelum dipakai di lapangan.
insert into public.dining_tables (label, qr_token_hash) values
  ('[DEMO] Meja 01', public.hash_table_token('dev-table-01-token')),
  ('[DEMO] Meja 02', public.hash_table_token('dev-table-02-token')),
  ('[DEMO] Meja 03', public.hash_table_token('dev-table-03-token')),
  ('[DEMO] Meja 04', public.hash_table_token('dev-table-04-token'))
on conflict (label) do nothing;

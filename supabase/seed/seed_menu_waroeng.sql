-- seed_menu_waroeng.sql
-- Seed menu NYATA Waroeng MeJeng Kampoeng: 2 kategori besar (Makanan &
-- Minuman) sesuai permintaan usaha — UI POS kasir cukup 2 filter.
-- 75 varian: 72 aktif dijual + 3 add-on nonaktif. TIDAK memuat label [DEMO].
-- Idempoten: jalankan berulang tanpa menggandakan data.
--
-- Kebijakan add-on (Tahu/Tempe/Ketimun): harga BELUM ditentukan →
-- di-seed dengan price 0 + is_active = false. Setelah operator menentukan
-- harga, aktifkan lewat Menu & Harga di POS (menu tetap tersembunyi dari
-- pelanggan sampai aktif — tanpa harga palsu di menu publik).
--
-- Varian ukuran: Mie Nasi Goreng (13rb/18rb) & Nasi Goreng (10rb/15rb)
-- memakai modifier opsional "Besar (+Rp5.000)" (max 1 pilihan).
-- Menu minuman panas diberi imbuhan "Panas" pada nama (Beng-Beng Panas
-- Susu, dst.) agar tidak tabrakan nama dengan varian dinginnya.

-- ---------------------------------------------------------------------------
-- 1. Kategori (2 besar)
-- ---------------------------------------------------------------------------
insert into public.product_categories (name, sort_order)
values
  ('Makanan', 1),
  ('Minuman', 2)
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Produk (75 varian)
-- ---------------------------------------------------------------------------
insert into public.products (category_id, name, price, is_active)
select c.id, v.name, v.price, v.active
from (values
  -- ============================ MAKANAN (26) ============================
  -- Ayam dan Lauk
  ('Makanan', 'Ayam Geprek + Nasi', 13000, true),
  ('Makanan', 'Ayam Geprek Tanpa Nasi', 10000, true),
  ('Makanan', 'Ayam Bakar + Nasi', 13000, true),
  ('Makanan', 'Ayam Kremes + Nasi', 13000, true),
  ('Makanan', 'Ayam Kremes Tanpa Nasi', 10000, true),
  ('Makanan', 'Nasi Telur Dadar', 10000, true),
  ('Makanan', 'Nasi Lele Goreng / Bakar', 12000, true),
  -- Mie
  ('Makanan', 'Mie Tarempa', 13000, true),
  ('Makanan', 'Mie Rebus', 10000, true),
  ('Makanan', 'Mie Goreng', 10000, true),
  ('Makanan', 'Mie Nasi Goreng', 13000, true),  -- besar: +Rp5.000 (modifier)
  ('Makanan', 'Mie Pedas Level 1', 12000, true),
  ('Makanan', 'Mie Pedas Level 2', 13000, true),
  ('Makanan', 'Mie Pedas Level 3', 14000, true),
  ('Makanan', 'Mie Pedas Level 4', 15000, true),
  ('Makanan', 'Mie Pedas Level 5', 16000, true),
  -- Nasi
  ('Makanan', 'Nasi Goreng', 10000, true),      -- besar: +Rp5.000 (modifier)
  ('Makanan', 'Nasi Putih', 3000, true),
  -- Seblak
  ('Makanan', 'Seblak Biasa', 10000, true),
  ('Makanan', 'Seblak Komplit', 15000, true),
  -- Camilan dan Sambal
  ('Makanan', 'Corndog dan Tangsis', 5000, true),
  ('Makanan', 'Sambal Terasi', 3000, true),
  ('Makanan', 'Sambal Hijau', 3000, true),
  -- Add-ons — harga belum ditentukan: nonaktif dulu
  ('Makanan', 'Tahu', 0, false),
  ('Makanan', 'Tempe', 0, false),
  ('Makanan', 'Ketimun', 0, false),
  -- ============================ MINUMAN (49) ============================
  -- Teh dan Lemon Tea
  ('Minuman', 'Teh Merah Jumbo', 10000, true),
  ('Minuman', 'Teh Merah Besar', 5000, true),
  ('Minuman', 'Teh Merah Kecil', 3000, true),
  ('Minuman', 'Teh Hijau Jumbo', 10000, true),
  ('Minuman', 'Teh Hijau Besar', 5000, true),
  ('Minuman', 'Teh Hijau Kecil', 3000, true),
  ('Minuman', 'Lemon Tea', 7000, true),
  ('Minuman', 'Teh Susu', 8000, true),
  ('Minuman', 'Teh Tarik Biasa', 5000, true),
  ('Minuman', 'Teh Tarik + Gula', 7000, true),
  ('Minuman', 'Teh Tarik Susu', 8000, true),
  -- Nutrisari dan Minuman Lainnya
  ('Minuman', 'Nutrisari (Pilih Rasa)', 5000, true),
  ('Minuman', 'Nutrisari Cincau Biasa', 7000, true),
  ('Minuman', 'Nutrisari Cincau Double Cincau', 10000, true),
  ('Minuman', 'Es Kosong', 3000, true),
  ('Minuman', 'Susu', 8000, true),
  -- Bontea
  ('Minuman', 'Bontea Biasa', 5000, true),
  ('Minuman', 'Bontea + Gula', 7000, true),
  ('Minuman', 'Bontea Susu', 8000, true),
  -- Chocolatos
  ('Minuman', 'Chocolatos Biasa', 5000, true),
  ('Minuman', 'Chocolatos + Gula', 7000, true),
  ('Minuman', 'Chocolatos Susu', 8000, true),
  -- Milo
  ('Minuman', 'Milo Biasa', 5000, true),
  ('Minuman', 'Milo + Gula', 7000, true),
  ('Minuman', 'Milo Susu', 8000, true),
  -- Cappuccino
  ('Minuman', 'Cappuccino Biasa', 5000, true),
  ('Minuman', 'Cappuccino + Gula', 7000, true),
  ('Minuman', 'Cappuccino Susu', 8000, true),
  -- Beng-Beng
  ('Minuman', 'Beng-Beng Biasa', 5000, true),
  ('Minuman', 'Beng-Beng + Gula', 7000, true),
  ('Minuman', 'Beng-Beng Susu', 8000, true),
  -- Kopi dan Good Day
  ('Minuman', 'Kopi Susu Gelas Kecil', 5000, true),
  ('Minuman', 'Kopi Susu Gelas Besar', 10000, true),
  ('Minuman', 'Kopi TOP Biasa', 5000, true),
  ('Minuman', 'Kopi TOP + Gula', 7000, true),
  ('Minuman', 'Kopi TOP Susu', 8000, true),
  ('Minuman', 'Good Day Biasa', 5000, true),
  ('Minuman', 'Good Day + Gula', 7000, true),
  ('Minuman', 'Good Day Susu', 8000, true),
  -- Kopi Panas
  ('Minuman', 'Kopi Kapal Api', 5000, true),
  ('Minuman', 'Kopi Kapal Api Susu', 8000, true),
  ('Minuman', 'Kopi TOP Gula Aren', 5000, true),
  ('Minuman', 'Kopi TOP Gula Aren Susu', 8000, true),
  -- Beng-Beng Panas
  ('Minuman', 'Beng-Beng Panas Biasa', 7000, true),
  ('Minuman', 'Beng-Beng Panas + Gula', 8000, true),
  ('Minuman', 'Beng-Beng Panas Susu', 10000, true),
  -- Cappuccino Panas
  ('Minuman', 'Cappuccino Panas Biasa', 7000, true),
  ('Minuman', 'Cappuccino Panas + Gula', 8000, true),
  ('Minuman', 'Cappuccino Panas Susu', 10000, true)
) as v(cat, name, price, active)
join public.product_categories c on c.name = v.cat
where not exists (
  select 1 from public.products p
  where p.name = v.name and p.category_id = c.id
);

-- ---------------------------------------------------------------------------
-- 3. Modifier "Besar" (+Rp5.000) untuk menu dua harga
-- ---------------------------------------------------------------------------
insert into public.modifiers (name, price_delta)
select 'Besar', 5000
where not exists (
  select 1 from public.modifiers m
  where m.name = 'Besar' and m.price_delta = 5000
);

insert into public.product_modifiers (product_id, modifier_id, min_select, max_select)
select p.id, m.id, 0, 1
from public.products p
join public.product_categories c on c.id = p.category_id
cross join public.modifiers m
where m.name = 'Besar' and m.price_delta = 5000
  and ((c.name = 'Makanan' and p.name = 'Mie Nasi Goreng')
    or (c.name = 'Makanan' and p.name = 'Nasi Goreng'))
on conflict do nothing;

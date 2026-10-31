-- seed_menu_waroeng.sql
-- Seed menu NYATA Waroeng MeJeng Kampoeng: 17 kategori, 72 menu + 3 add-on
-- (75 varian). TIDAK memuat label [DEMO] — aman untuk produksi.
-- Idempoten: jalankan berulang tanpa menggandakan data.
--
-- Kebijakan add-on (Tahu/Tempe/Ketimun): harga BELUM ditentukan →
-- di-seed dengan price 0 + is_active = false. Setelah operator menentukan
-- harga, aktifkan lewat Menu & Harga di POS (menu tetap tersembunyi dari
-- pelanggan sampai aktif — tanpa harga palsu di menu publik).
--
-- Varian ukuran: Mie Nasi Goreng (13rb/18rb) & Nasi Goreng (10rb/15rb)
-- memakai modifier opsional "Besar (+Rp5.000)" (max 1 pilihan).

-- ---------------------------------------------------------------------------
-- 1. Kategori
-- ---------------------------------------------------------------------------
insert into public.product_categories (name, sort_order)
values
  ('Ayam dan Lauk', 1),
  ('Mie', 2),
  ('Nasi', 3),
  ('Seblak', 4),
  ('Camilan dan Sambal', 5),
  ('Add-ons Makanan', 6),
  ('Teh dan Lemon Tea', 7),
  ('Nutrisari dan Minuman Lainnya', 8),
  ('Bontea', 9),
  ('Chocolatos', 10),
  ('Milo', 11),
  ('Cappuccino', 12),
  ('Beng-Beng', 13),
  ('Kopi dan Good Day', 14),
  ('Kopi Panas', 15),
  ('Beng-Beng Panas', 16),
  ('Cappuccino Panas', 17)
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Produk (75 varian)
-- ---------------------------------------------------------------------------
insert into public.products (category_id, name, price, is_active)
select c.id, v.name, v.price, v.active
from (values
  -- A1. Ayam dan Lauk
  ('Ayam dan Lauk', 'Ayam Geprek + Nasi', 13000, true),
  ('Ayam dan Lauk', 'Ayam Geprek Tanpa Nasi', 10000, true),
  ('Ayam dan Lauk', 'Ayam Bakar + Nasi', 13000, true),
  ('Ayam dan Lauk', 'Ayam Kremes + Nasi', 13000, true),
  ('Ayam dan Lauk', 'Ayam Kremes Tanpa Nasi', 10000, true),
  ('Ayam dan Lauk', 'Nasi Telur Dadar', 10000, true),
  ('Ayam dan Lauk', 'Nasi Lele Goreng / Bakar', 12000, true),
  -- A2. Mie
  ('Mie', 'Mie Tarempa', 13000, true),
  ('Mie', 'Mie Rebus', 10000, true),
  ('Mie', 'Mie Goreng', 10000, true),
  ('Mie', 'Mie Nasi Goreng', 13000, true),  -- besar: +Rp5.000 (modifier)
  ('Mie', 'Mie Pedas Level 1', 12000, true),
  ('Mie', 'Mie Pedas Level 2', 13000, true),
  ('Mie', 'Mie Pedas Level 3', 14000, true),
  ('Mie', 'Mie Pedas Level 4', 15000, true),
  ('Mie', 'Mie Pedas Level 5', 16000, true),
  -- A3. Nasi
  ('Nasi', 'Nasi Goreng', 10000, true),      -- besar: +Rp5.000 (modifier)
  ('Nasi', 'Nasi Putih', 3000, true),
  -- A4. Seblak
  ('Seblak', 'Seblak Biasa', 10000, true),
  ('Seblak', 'Seblak Komplit', 15000, true),
  -- A5. Camilan dan Sambal
  ('Camilan dan Sambal', 'Corndog dan Tangsis', 5000, true),
  ('Camilan dan Sambal', 'Sambal Terasi', 3000, true),
  ('Camilan dan Sambal', 'Sambal Hijau', 3000, true),
  -- A6. Add-ons Makanan — harga belum ditentukan: nonaktif dulu
  ('Add-ons Makanan', 'Tahu', 0, false),
  ('Add-ons Makanan', 'Tempe', 0, false),
  ('Add-ons Makanan', 'Ketimun', 0, false),
  -- B1. Teh dan Lemon Tea
  ('Teh dan Lemon Tea', 'Teh Merah Jumbo', 10000, true),
  ('Teh dan Lemon Tea', 'Teh Merah Besar', 5000, true),
  ('Teh dan Lemon Tea', 'Teh Merah Kecil', 3000, true),
  ('Teh dan Lemon Tea', 'Teh Hijau Jumbo', 10000, true),
  ('Teh dan Lemon Tea', 'Teh Hijau Besar', 5000, true),
  ('Teh dan Lemon Tea', 'Teh Hijau Kecil', 3000, true),
  ('Teh dan Lemon Tea', 'Lemon Tea', 7000, true),
  ('Teh dan Lemon Tea', 'Teh Susu', 8000, true),
  ('Teh dan Lemon Tea', 'Teh Tarik Biasa', 5000, true),
  ('Teh dan Lemon Tea', 'Teh Tarik + Gula', 7000, true),
  ('Teh dan Lemon Tea', 'Teh Tarik Susu', 8000, true),
  -- B2. Nutrisari dan Minuman Lainnya
  ('Nutrisari dan Minuman Lainnya', 'Nutrisari (Pilih Rasa)', 5000, true),
  ('Nutrisari dan Minuman Lainnya', 'Nutrisari Cincau Biasa', 7000, true),
  ('Nutrisari dan Minuman Lainnya', 'Nutrisari Cincau Double Cincau', 10000, true),
  ('Nutrisari dan Minuman Lainnya', 'Es Kosong', 3000, true),
  ('Nutrisari dan Minuman Lainnya', 'Susu', 8000, true),
  -- B3. Bontea
  ('Bontea', 'Bontea Biasa', 5000, true),
  ('Bontea', 'Bontea + Gula', 7000, true),
  ('Bontea', 'Bontea Susu', 8000, true),
  -- B4. Chocolatos
  ('Chocolatos', 'Chocolatos Biasa', 5000, true),
  ('Chocolatos', 'Chocolatos + Gula', 7000, true),
  ('Chocolatos', 'Chocolatos Susu', 8000, true),
  -- B5. Milo
  ('Milo', 'Milo Biasa', 5000, true),
  ('Milo', 'Milo + Gula', 7000, true),
  ('Milo', 'Milo Susu', 8000, true),
  -- B6. Cappuccino
  ('Cappuccino', 'Cappuccino Biasa', 5000, true),
  ('Cappuccino', 'Cappuccino + Gula', 7000, true),
  ('Cappuccino', 'Cappuccino Susu', 8000, true),
  -- B7. Beng-Beng
  ('Beng-Beng', 'Beng-Beng Biasa', 5000, true),
  ('Beng-Beng', 'Beng-Beng + Gula', 7000, true),
  ('Beng-Beng', 'Beng-Beng Susu', 8000, true),
  -- B8. Kopi dan Good Day
  ('Kopi dan Good Day', 'Kopi Susu Gelas Kecil', 5000, true),
  ('Kopi dan Good Day', 'Kopi Susu Gelas Besar', 10000, true),
  ('Kopi dan Good Day', 'Kopi TOP Biasa', 5000, true),
  ('Kopi dan Good Day', 'Kopi TOP + Gula', 7000, true),
  ('Kopi dan Good Day', 'Kopi TOP Susu', 8000, true),
  ('Kopi dan Good Day', 'Good Day Biasa', 5000, true),
  ('Kopi dan Good Day', 'Good Day + Gula', 7000, true),
  ('Kopi dan Good Day', 'Good Day Susu', 8000, true),
  -- C1. Kopi Panas
  ('Kopi Panas', 'Kopi Kapal Api', 5000, true),
  ('Kopi Panas', 'Kopi Kapal Api Susu', 8000, true),
  ('Kopi Panas', 'Kopi TOP Gula Aren', 5000, true),
  ('Kopi Panas', 'Kopi TOP Gula Aren Susu', 8000, true),
  -- C2. Beng-Beng Panas
  ('Beng-Beng Panas', 'Beng-Beng Biasa', 7000, true),
  ('Beng-Beng Panas', 'Beng-Beng + Gula', 8000, true),
  ('Beng-Beng Panas', 'Beng-Beng Susu', 10000, true),
  -- C3. Cappuccino Panas
  ('Cappuccino Panas', 'Cappuccino Biasa', 7000, true),
  ('Cappuccino Panas', 'Cappuccino + Gula', 8000, true),
  ('Cappuccino Panas', 'Cappuccino Susu', 10000, true)
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
  and ((c.name = 'Mie' and p.name = 'Mie Nasi Goreng')
    or (c.name = 'Nasi' and p.name = 'Nasi Goreng'))
on conflict do nothing;

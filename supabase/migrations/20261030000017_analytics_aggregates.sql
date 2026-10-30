-- 0017_analytics_aggregates.sql
-- Persiapan data post-MVP (D-06, docs/ml-roadmap.md): AGREGAT deterministik
-- dari tabel yang sudah ada. TANPA prediksi, TANPA model, TANPA tabel forecast
-- (PRD §9 melarang ML di MVP; nama forecast_runs / AI Insights dilarang di sini).
--
-- Tujuan: (a) histori transaksi siap dilatih nanti tanpa mengubah skema lagi,
-- (b) laporan bisa membaca agregat tanpa scan penuh tiap kali dibuka.
-- Seluruh view memakai security_invoker=true sehingga RLS tabel dasar tetap
-- berlaku; grant hanya ke authenticated (anon tidak punya akses).

-- ---------------------------------------------------------------------------
-- 1. Indeks yang dibutuhkan agregat waktu & produk.
-- ---------------------------------------------------------------------------
create index if not exists sales_created_at_idx
  on public.sales (created_at);
create index if not exists sale_items_product_idx
  on public.sale_items (product_id, sale_id);

-- ---------------------------------------------------------------------------
-- 2. Fondasi: satu baris per item terjual dengan dimensi waktu WIB.
--    Hari/jam dihitung `at time zone 'Asia/Jakarta'` (pola 0011/D-04 di SQL).
-- ---------------------------------------------------------------------------
create or replace view public.v_sale_item_facts
with (security_invoker = true) as
select
  si.id as sale_item_id,
  s.id as sale_id,
  s.receipt_no,
  si.product_id,
  si.product_name,
  s.dining_type,
  s.table_id,
  s.status as sale_status,
  (s.created_at at time zone 'Asia/Jakarta')::date as sale_day,
  date_trunc('hour', s.created_at at time zone 'Asia/Jakarta') as sale_hour,
  extract(isodow from s.created_at at time zone 'Asia/Jakarta')::int
    as day_of_week,            -- 1=Senin … 7=Minggu
  extract(hour from s.created_at at time zone 'Asia/Jakarta')::int
    as hour_of_day,            -- 0..23 WIB
  si.qty,
  si.unit_price,
  si.qty * si.unit_price as line_revenue
from public.sale_items si
join public.sales s on s.id = si.sale_id;

-- ---------------------------------------------------------------------------
-- 3. Agregat uang per hari dan per jam (grain = transaksi, bukan item,
--    sehingga total uang tidak terhitung ganda saat join ke item).
-- ---------------------------------------------------------------------------
create or replace view public.v_sales_daily
with (security_invoker = true) as
select
  (s.created_at at time zone 'Asia/Jakarta')::date as sale_day,
  extract(isodow from s.created_at at time zone 'Asia/Jakarta')::int
    as day_of_week,
  count(*) as transactions,
  count(*) filter (where s.status <> 'REFUNDED') as counted_transactions,
  count(*) filter (where s.dining_type = 'DINE_IN') as dine_in_transactions,
  count(*) filter (where s.dining_type = 'TAKEAWAY') as takeaway_transactions,
  coalesce(sum(s.total), 0) as gross_total,
  coalesce(sum(s.discount_amount), 0) as discount_total,
  coalesce(sum(s.tax_amount), 0) as tax_total,
  coalesce(sum(s.service_amount), 0) as service_total,
  coalesce(sum(s.refund_amount), 0) as refund_total,
  coalesce(sum(s.total - s.refund_amount), 0) as net_total
from public.sales s
group by 1, 2;

create or replace view public.v_sales_hourly
with (security_invoker = true) as
select
  date_trunc('hour', s.created_at at time zone 'Asia/Jakarta') as sale_hour,
  (s.created_at at time zone 'Asia/Jakarta')::date as sale_day,
  count(*) as transactions,
  count(*) filter (where s.status <> 'REFUNDED') as counted_transactions,
  count(*) filter (where s.dining_type = 'DINE_IN') as dine_in_transactions,
  coalesce(sum(s.total - s.refund_amount), 0) as net_total
from public.sales s
group by 1, 2;

-- ---------------------------------------------------------------------------
-- 4. Agregat qty/omzet per menu per hari (bahan baku training demand).
--    Sale REFUNDED dikecualikan (barang kembali); refund sebagian TIDAK
--    dikurangi di sini -- jumlah pastinya ada di tabel `refunds`.
--    Nama menu di-snapshot per transaksi, jadi rename menu menghasilkan
--    baris berbeda (jujur terhadap data, bukan digabung paksa).
-- ---------------------------------------------------------------------------
create or replace view public.v_product_daily
with (security_invoker = true) as
select
  f.sale_day,
  f.day_of_week,
  f.product_id,
  f.product_name,
  count(distinct f.sale_id) as transactions,
  sum(f.qty) as qty,
  coalesce(sum(f.line_revenue), 0) as revenue
from public.v_sale_item_facts f
where f.sale_status <> 'REFUNDED'
group by 1, 2, 3, 4;

-- ---------------------------------------------------------------------------
-- 5. Pergerakan bahan per hari: PURCHASE = masuk, RECIPE/PRODUCTION = terpakai,
--    WASTE = susut, ADJUSTMENT = koreksi (boleh +/-).
-- ---------------------------------------------------------------------------
create or replace view public.v_stock_usage_daily
with (security_invoker = true) as
select
  (m.created_at at time zone 'Asia/Jakarta')::date as movement_day,
  m.ingredient_id,
  m.source,
  sum(m.qty_delta) as qty_delta,
  sum(case when m.qty_delta > 0 then m.qty_delta else 0 end) as qty_in,
  sum(case when m.qty_delta < 0 then -m.qty_delta else 0 end) as qty_out,
  count(*) as movements
from public.stock_movements m
group by 1, 2, 3;

-- ---------------------------------------------------------------------------
-- 6. Izin: cuma sesi login; anon/pubic dicabut (laporan = data privat).
-- ---------------------------------------------------------------------------
do $$
declare
  v text;
begin
  foreach v in array array[
    'v_sale_item_facts', 'v_sales_daily', 'v_sales_hourly',
    'v_product_daily', 'v_stock_usage_daily'
  ]
  loop
    execute format('revoke all on public.%I from public, anon', v);
    execute format('grant select on public.%I to authenticated', v);
  end loop;
end $$;

-- 0020_recommendations.sql
-- Fase R1 rekomendasi NON-ML (docs/rfc-rekomendasi-hpp-energi.md):
--   1. inv_hpp_alerts — peringatan harga bahan: unit_cost terkini vs
--      rata-rata tertimbang pembelian N hari terakhir, beserta dampak
--      per porsi pada setiap menu yang memakai bahan itu di resep aktif.
--   2. exp_energy_calibration — kalibrasi kalkulator: total ESTIMATED vs
--      ACTUAL (LISTRIK/LPG) pada rentang tanggal + deviasi + faktor
--      koreksi yang disarankan.
-- Keduanya STATISTIK DESKRIPTIF murni (tanpa model, tanpa prediksi —
-- tetap dalam koridor PRD §9 bahkan sebelum amendemen): baca saja,
-- tidak mengubah uang, tidak menulis data. Guard is_operator seragam
-- (pola 0015/0019). Uang integer Rupiah.

-- ---------------------------------------------------------------------------
-- 1. inv_hpp_alerts: bahan resep aktif yang harganya menyimpang dari
--    rata-rata pembelian jendela. Riwayat = pembelian RECEIVED pada
--    purchased_at >= (hari WIB - p_window_days), rata-rata TERTIMBANG
--    (sum total / sum qty — bukan rerata baris, agar pembelian besar
--    tidak diperlakukan sama dengan pembelian kecil).
--    Tanpa riwayat dalam jendela -> TIDAK ada pembanding -> tidak masuk
--    daftar (jujur: "belum ada pembanding", bukan angka karangan).
-- ---------------------------------------------------------------------------
create or replace function public.inv_hpp_alerts(
  p_threshold_pct integer default 10,
  p_window_days integer default 90
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_result jsonb;
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  if p_threshold_pct is null or p_threshold_pct < 1 or p_threshold_pct > 500 then
    raise exception 'invalid_threshold' using errcode = 'P0001';
  end if;
  if p_window_days is null or p_window_days < 7 or p_window_days > 730 then
    raise exception 'invalid_window' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_build_object(
    'threshold_pct', p_threshold_pct,
    'window_days', p_window_days,
    'alerts', coalesce((
      select jsonb_agg(a ORDER BY abs(a.delta_pct) DESC, a.name)
      from (
        select
          i.id as ingredient_id,
          i.name,
          i.base_unit,
          i.unit_cost,
          round(h.avg_cost)::bigint as avg_cost,
          round((i.unit_cost - h.avg_cost) / h.avg_cost * 100, 1)
            as delta_pct,
          case when i.unit_cost > h.avg_cost then 'NAIK'
               else 'TURUN' end as direction,
          h.purchases,
          coalesce((
            select jsonb_agg(jsonb_build_object(
                     'product_id', u.product_id,
                     'product_name', u.product_name,
                     'hpp_delta_per_portion',
                       round(u.qty * (i.unit_cost - h.avg_cost)
                             / u.yield_qty, 2)
                   ) ORDER BY u.product_name)
            from (
              select rv.product_id,
                     pr.name as product_name,
                     rv.yield_qty,
                     ri.qty
              from public.recipe_items ri
              join public.recipe_versions rv
                on rv.id = ri.recipe_version_id and rv.is_active
              join public.products pr
                on pr.id = rv.product_id and pr.archived_at is null
              where ri.ingredient_id = i.id
            ) u
          ), '[]'::jsonb) as products
        from public.ingredients i
        join (
          select pi.ingredient_id,
                 sum(pi.qty * pi.unit_cost) / nullif(sum(pi.qty), 0)
                   as avg_cost,
                 count(distinct pi.purchase_id) as purchases
          from public.purchase_items pi
          join public.purchases p on p.id = pi.purchase_id
          where p.status = 'RECEIVED'
            and p.purchased_at >=
                (now() at time zone 'Asia/Jakarta')::date - p_window_days
          group by pi.ingredient_id
          having sum(pi.qty) > 0
        ) h on h.ingredient_id = i.id
        where h.avg_cost > 0
          and i.unit_cost > 0
          and abs(i.unit_cost - h.avg_cost) / h.avg_cost * 100
              >= p_threshold_pct
      ) a
    ), '[]'::jsonb)
  ), '{}'::jsonb) into v_result;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. exp_energy_calibration: apakah kalkulator meleset dari tagihan asli?
--    ESTIMATED (dari kalkulator & asumsi manual) vs ACTUAL (tagihan
--    nyata) untuk LISTRIK & LPG pada rentang (default: 29 hari terakhir
--    WIB sampai hari ini, i.e. 30 hari inklusif).
--    JUJUR TERHADAP DATA SEIMBANG: deviasi/faktor HANYA dihitung dari
--    jenis yang punya KEDUA sisi (estimated>0 dan actual>0) pada rentang
--    — mencampur jenis yang belum punya tagihan asli menyesatkan (mis.
--    estimasi LPG tanpa tagihan LPG "mengencerkan" deviasi listrik).
--    compared_estimated/compared_actual = subset pembanding itu;
--    estimated_total/actual_total = seluruh data (untuk tampilan).
--    Tidak ada jenis yang seimbang -> enough_data false, deviasi/faktor
--    null (bukan nol karangan). Hasil HANYA saran tampilan; biaya
--    aktual tetap yang mengurangi margin, tidak ada yang diubah.
-- ---------------------------------------------------------------------------
create or replace function public.exp_energy_calibration(
  p_from date default null,
  p_to date default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_to date := coalesce(
    p_to, (now() at time zone 'Asia/Jakarta')::date);
  v_from date := coalesce(p_from, v_to - 29);
  v_est integer := 0;
  v_act integer := 0;
  v_cmp_est integer := 0;
  v_cmp_act integer := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  if v_from > v_to then
    raise exception 'invalid_range' using errcode = 'P0001';
  end if;
  if v_to - v_from > 730 then
    raise exception 'range_too_long' using errcode = 'P0001';
  end if;

  -- Ringkasan per jenis (untuk tampilan) + agregat jenis yang layak
  -- dibandingkan (dua sisi > 0) untuk deviasi/faktor.
  with per_type as (
    select type,
           coalesce(sum(amount) filter (where kind = 'ESTIMATED'), 0)
             as estimated,
           coalesce(sum(amount) filter (where kind = 'ACTUAL'), 0)
             as actual,
           count(*) filter (where kind = 'ESTIMATED') as estimated_count,
           count(*) filter (where kind = 'ACTUAL') as actual_count
    from public.expenses
    where type in ('LISTRIK', 'LPG')
      and expense_date between v_from and v_to
    group by type
  )
  select
    coalesce(sum(t.estimated), 0),
    coalesce(sum(t.actual), 0),
    coalesce(sum(t.estimated) filter (where t.estimated > 0
                                      and t.actual > 0), 0),
    coalesce(sum(t.actual) filter (where t.estimated > 0
                                   and t.actual > 0), 0),
    coalesce(jsonb_agg(
      to_jsonb(t.*) || jsonb_build_object(
        'deviation_pct', case
          when t.estimated > 0 and t.actual > 0 then
            round((t.actual - t.estimated) * 100.0 / t.estimated, 1)
        end,
        'suggested_factor', case
          when t.estimated > 0 and t.actual > 0 then
            round(t.actual::numeric / t.estimated, 3)
        end)
      order by t.type), '[]'::jsonb)
  into v_est, v_act, v_cmp_est, v_cmp_act, v_rows
  from per_type t;

  return jsonb_build_object(
    'd_from', v_from,
    'd_to', v_to,
    'estimated_total', v_est,
    'actual_total', v_act,
    'compared_estimated', v_cmp_est,
    'compared_actual', v_cmp_act,
    'deviation_pct', case
      when v_cmp_est > 0 and v_cmp_act > 0 then
        round((v_cmp_act - v_cmp_est) * 100.0 / v_cmp_est, 1)
    end,
    'suggested_factor', case
      when v_cmp_est > 0 and v_cmp_act > 0 then
        round(v_cmp_act::numeric / v_cmp_est, 3)
    end,
    'enough_data', (v_cmp_est > 0 and v_cmp_act > 0),
    'by_type', v_rows
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Grants: wrapper operator saja (baca sensitif: biaya & harga beli);
--    anon/public tidak memegang apa pun di jalur ini.
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'inv_hpp_alerts(integer, integer)',
    'exp_energy_calibration(date, date)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format(
      'grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

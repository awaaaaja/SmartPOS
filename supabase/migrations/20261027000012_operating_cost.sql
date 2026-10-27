-- 20261027000012_operating_cost.sql
-- Sprint 05 (S05-01…S05-09): energi, biaya operasional, alokasi, kas shift,
-- laporan. Pola Sprint 04: operator hanya MEMBACA; semua tulisan lewat
-- fungsi SECURITY DEFINER agar aturan (alokasi ≤ sumber, satu shift
-- terbuka, estimasi ≠ aktual) berlaku di server.
-- Uang integer Rupiah. Tidak ada AI/forecast; laporan = statistik deskriptif.

-- ---------------------------------------------------------------------------
-- S05-03: biaya operasional. ESTIMATED (asumsi) vs ACTUAL (tagihan nyata)
-- tidak pernah digabung buta.
-- ---------------------------------------------------------------------------
create table if not exists public.expenses (
  id bigint generated always as identity primary key,
  type text not null check (type in (
    'LISTRIK', 'LPG', 'AIR', 'KEMASAN', 'SEWA', 'INTERNET', 'LAINNYA')),
  description text not null check (length(trim(description)) >= 3),
  amount integer not null check (amount >= 0),
  kind text not null check (kind in ('ESTIMATED', 'ACTUAL')),
  evidence_url text,                       -- bukti opsional (URL)
  expense_date date not null
    default (now() at time zone 'Asia/Jakarta')::date,
  source_ref text,                         -- mis. 'energy_estimate:12'
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- S05-01/02: perhitungan energi tersimpan terpisah sebagai asumsi,
-- selalu ikut sebagai expense ESTIMATED (bukan ACTUAL).
-- ---------------------------------------------------------------------------
create table if not exists public.energy_estimates (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('ELECTRICITY', 'LPG')),
  -- Listrik: kWh = watt x jam x faktor_beban(%) / 100 / 1000
  watt numeric check (watt is null or watt > 0),
  hours numeric check (hours is null or hours > 0),
  load_factor numeric check (
    load_factor is null or (load_factor > 0 and load_factor <= 100)),
  tariff numeric check (tariff is null or tariff >= 0),  -- Rp/kWh
  -- LPG: biaya = (isi_ulang / jam_efektif) x jam_batch
  refill_price integer check (
    refill_price is null or refill_price >= 0),
  effective_hours numeric check (
    effective_hours is null or effective_hours > 0),
  batch_hours numeric check (batch_hours is null or batch_hours >= 0),
  -- Umum
  portions integer not null check (portions > 0),
  kwh numeric,                             -- hanya ELECTRICITY
  cost integer not null check (cost >= 0), -- Rp dibulatkan server
  note text,
  expense_id bigint not null references public.expenses (id),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- S05-04: alokasi biaya ke target (batch/menu/periode). Total alokasi per
-- expense DILARANG melebihi sumber — dicek server, bukan UI.
-- ---------------------------------------------------------------------------
create table if not exists public.cost_allocations (
  id bigint generated always as identity primary key,
  expense_id bigint not null references public.expenses (id)
    on delete cascade,
  target_ref text not null check (length(trim(target_ref)) >= 2),
  amount integer not null check (amount > 0),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (expense_id, target_ref)
);

-- ---------------------------------------------------------------------------
-- S05-05: kas shift. Satu shift terbuka; expected dihitung server dari
-- penjualan TUNAI saja (transfer/QRIS tidak menambah uang fisik).
-- ---------------------------------------------------------------------------
create table if not exists public.cash_shifts (
  id bigint generated always as identity primary key,
  status text not null default 'OPEN'
    check (status in ('OPEN', 'CLOSED')),
  opening_cash integer not null check (opening_cash >= 0),
  expected_cash integer check (expected_cash is null or expected_cash >= 0),
  actual_cash integer check (actual_cash is null or actual_cash >= 0),
  variance integer,                         -- actual - expected (boleh negatif)
  note text,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  created_by uuid default auth.uid(),
  closed_by uuid
);
-- Satu shift terbuka pada satu waktu (PRD §7).
create unique index if not exists cash_shifts_one_open
  on public.cash_shifts (status) where status = 'OPEN';

-- ---------------------------------------------------------------------------
-- RLS: operator hanya MEMBACA (pola Sprint 04).
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'expenses', 'energy_estimates', 'cost_allocations', 'cash_shifts'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists operator_read on public.%I', t);
    execute format(
      'create policy operator_read on public.%I for select to authenticated '
      'using (public.is_operator())', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- S05-03: simpan biaya (baru/ubah). Validasi & audit di server.
-- ---------------------------------------------------------------------------
create or replace function public.exp_save(
  p_id bigint default null,
  p_type text default null,
  p_description text default null,
  p_amount integer default null,
  p_kind text default 'ACTUAL',
  p_expense_date date default null,
  p_evidence_url text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id bigint;
  v_date date := coalesce(
    p_expense_date, (now() at time zone 'Asia/Jakarta')::date);
begin
  if p_type not in (
    'LISTRIK', 'LPG', 'AIR', 'KEMASAN', 'SEWA', 'INTERNET', 'LAINNYA') then
    raise exception 'invalid_type' using errcode = 'P0001';
  end if;
  if p_kind not in ('ESTIMATED', 'ACTUAL') then
    raise exception 'invalid_kind' using errcode = 'P0001';
  end if;
  if p_description is null or length(trim(p_description)) < 3 then
    raise exception 'invalid_description' using errcode = 'P0001';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'invalid_amount' using errcode = 'P0001';
  end if;

  if p_id is null then
    insert into public.expenses
      (type, description, amount, kind, expense_date, evidence_url)
    values (p_type, trim(p_description), p_amount, p_kind, v_date,
            nullif(trim(coalesce(p_evidence_url, '')), ''))
    returning id into v_id;
  else
    update public.expenses
       set type = p_type,
           description = trim(p_description),
           amount = p_amount,
           kind = p_kind,
           expense_date = v_date,
           evidence_url = nullif(trim(coalesce(p_evidence_url, '')), '')
     where id = p_id
     returning id into v_id;
    if not found then
      raise exception 'expense_not_found' using errcode = 'P0001';
    end if;
    -- Sumber alokasi berubah: pastikan alokasi lama masih ≤ sumber baru.
    if (select coalesce(sum(amount), 0) from public.cost_allocations
        where expense_id = v_id) > p_amount then
      raise exception 'allocation_exceeds_source'
        using errcode = 'P0001',
              hint = 'Total alokasi melebihi nominal biaya.';
    end if;
  end if;

  insert into public.audit_events (entity, entity_id, action, detail,
                                   created_by)
  values ('expense', v_id::text, 'SAVE',
          jsonb_build_object('type', p_type, 'amount', p_amount,
                             'kind', p_kind, 'date', v_date),
          auth.uid());

  return (select jsonb_build_object(
    'id', id, 'type', type, 'description', description, 'amount', amount,
    'kind', kind, 'expense_date', expense_date, 'evidence_url', evidence_url,
    'source_ref', source_ref, 'created_at', created_at)
    from public.expenses where id = v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- S05-01/02: simpan estimasi energi. Rumus dihitung ULANG oleh server
-- (input UI hanya tampilan); selalu membuat expense ESTIMATED — asumsi
-- tidak pernah menjadi aktual secara diam-diam.
-- ---------------------------------------------------------------------------
create or replace function public.energy_save_estimate(
  p_kind text default null,
  p_watt numeric default null,
  p_hours numeric default null,
  p_load_factor numeric default null,
  p_tariff numeric default null,
  p_refill_price integer default null,
  p_effective_hours numeric default null,
  p_batch_hours numeric default null,
  p_portions integer default null,
  p_note text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_kwh numeric;
  v_cost integer;
  v_expense_id bigint;
  v_est_id bigint;
  v_type text;
  v_exp_id bigint;
begin
  if p_kind not in ('ELECTRICITY', 'LPG') then
    raise exception 'invalid_kind' using errcode = 'P0001';
  end if;
  if p_portions is null or p_portions <= 0 then
    raise exception 'invalid_portions' using errcode = 'P0001';
  end if;

  if p_kind = 'ELECTRICITY' then
    -- kWh = watt x jam x faktor_beban(%) / 100 / 1000 (PRD §6.3)
    if p_watt is null or p_watt <= 0
       or p_hours is null or p_hours <= 0
       or p_load_factor is null or p_load_factor <= 0
       or p_load_factor > 100
       or p_tariff is null or p_tariff < 0 then
      raise exception 'invalid_electricity_input'
        using errcode = 'P0001';
    end if;
    v_kwh := round((p_watt * p_hours * p_load_factor / 100 / 1000)::numeric,
                   3);
    v_cost := round((v_kwh * p_tariff)::numeric)::integer;
    v_type := 'LISTRIK';
  else
    if p_refill_price is null or p_refill_price < 0
       or p_effective_hours is null or p_effective_hours <= 0
       or p_batch_hours is null or p_batch_hours < 0 then
      raise exception 'invalid_lpg_input' using errcode = 'P0001';
    end if;
    v_kwh := null;
    v_cost := round(
      (p_refill_price::numeric / p_effective_hours * p_batch_hours)
      ::numeric)::integer;
    v_type := 'LPG';
  end if;

  insert into public.expenses
    (type, description, amount, kind, source_ref)
  values (v_type,
          case when p_kind = 'ELECTRICITY'
               then 'Estimasi listrik ' || v_kwh || ' kWh'
               else 'Estimasi LPG batch ' || p_batch_hours || ' jam' end,
          v_cost, 'ESTIMATED', null)
  returning id into v_expense_id;

  update public.expenses
     set source_ref = 'energy_estimate:' || v_expense_id::text
   where id = v_expense_id;

  insert into public.energy_estimates
    (kind, watt, hours, load_factor, tariff, refill_price,
     effective_hours, batch_hours, portions, kwh, cost, note, expense_id)
  values (p_kind, p_watt, p_hours, p_load_factor, p_tariff,
          p_refill_price, p_effective_hours, p_batch_hours, p_portions,
          v_kwh, v_cost, nullif(trim(coalesce(p_note, '')), ''),
          v_expense_id)
  returning id into v_est_id;

  insert into public.audit_events (entity, entity_id, action, detail,
                                   created_by)
  values ('energy_estimate', v_est_id::text, 'SAVE',
          jsonb_build_object('kind', p_kind, 'kwh', v_kwh,
                             'cost', v_cost, 'portions', p_portions),
          auth.uid());

  return (select jsonb_build_object(
    'estimate_id', id, 'kind', kind, 'kwh', kwh, 'cost', cost,
    'portions', portions, 'expense_id', expense_id, 'created_at', created_at)
    from public.energy_estimates where id = v_est_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- S05-04: alokasi biaya. Menolak bila total alokasi melebihi sumber.
-- ---------------------------------------------------------------------------
create or replace function public.cost_allocate(
  p_expense_id bigint default null,
  p_target_ref text default null,
  p_amount integer default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_src integer;
  v_used integer;
  v_id bigint;
begin
  if p_target_ref is null or length(trim(p_target_ref)) < 2 then
    raise exception 'invalid_target' using errcode = 'P0001';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount' using errcode = 'P0001';
  end if;

  select amount into v_src from public.expenses where id = p_expense_id
    for update;
  if not found then
    raise exception 'expense_not_found' using errcode = 'P0001';
  end if;

  select coalesce(sum(amount), 0) into v_used
    from public.cost_allocations where expense_id = p_expense_id;
  if v_used + p_amount > v_src then
    raise exception 'allocation_exceeds_source'
      using errcode = 'P0001',
            hint = 'Total alokasi melebihi nominal biaya.';
  end if;

  insert into public.cost_allocations (expense_id, target_ref, amount)
  values (p_expense_id, trim(p_target_ref), p_amount)
  on conflict (expense_id, target_ref)
  do update set amount = excluded.amount
  returning id into v_id;

  insert into public.audit_events (entity, entity_id, action, detail,
                                   created_by)
  values ('cost_allocation', v_id::text, 'ALLOCATE',
          jsonb_build_object('expense_id', p_expense_id,
                             'target', trim(p_target_ref),
                             'amount', p_amount),
          auth.uid());

  return (select jsonb_build_object(
    'expense_id', expense_id, 'target_ref', target_ref, 'amount', amount,
    'allocated_total', (select coalesce(sum(amount), 0)
                        from public.cost_allocations
                        where expense_id = p_expense_id))
    from public.cost_allocations where id = v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- S05-05: status kas shift (termasuk expected tunai live saat shift buka).
-- expected = kas awal + penjualan TUNAI (payment CASH) net refund.
-- ---------------------------------------------------------------------------
create or replace function public.cash_shift_status()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_shift public.cash_shifts%rowtype;
  v_expected integer;
  v_cash_sales integer;
begin
  select * into v_shift from public.cash_shifts
    where status = 'OPEN' order by opened_at desc limit 1;

  if v_shift.id is null then
    return jsonb_build_object('open', false);
  end if;

  select coalesce(sum(p.amount - s.refund_amount), 0)
    into v_cash_sales
    from public.payments p
    join public.sales s on s.id = p.sale_id
   where p.method = 'CASH' and p.created_at >= v_shift.opened_at;
  if v_cash_sales < 0 then
    v_cash_sales := 0;
  end if;
  v_expected := v_shift.opening_cash + v_cash_sales;

  return jsonb_build_object(
    'open', true,
    'shift_id', v_shift.id,
    'opening_cash', v_shift.opening_cash,
    'cash_sales', v_cash_sales,
    'expected_cash', v_expected,
    'opened_at', v_shift.opened_at);
end;
$$;

create or replace function public.cash_shift_open(
  p_opening_cash integer default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id bigint;
begin
  if p_opening_cash is null or p_opening_cash < 0 then
    raise exception 'invalid_opening_cash' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.cash_shifts where status = 'OPEN') then
    raise exception 'shift_already_open' using errcode = 'P0001';
  end if;

  insert into public.cash_shifts (opening_cash) values (p_opening_cash)
    returning id into v_id;

  insert into public.audit_events (entity, entity_id, action, detail,
                                   created_by)
  values ('cash_shift', v_id::text, 'OPEN',
          jsonb_build_object('opening_cash', p_opening_cash), auth.uid());

  return (select jsonb_build_object(
    'shift_id', id, 'opening_cash', opening_cash, 'opened_at', opened_at)
    from public.cash_shifts where id = v_id);
end;
$$;

create or replace function public.cash_shift_close(
  p_actual_cash integer default null,
  p_note text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_shift public.cash_shifts%rowtype;
  v_cash_sales integer;
  v_expected integer;
begin
  if p_actual_cash is null or p_actual_cash < 0 then
    raise exception 'invalid_actual_cash' using errcode = 'P0001';
  end if;

  select * into v_shift from public.cash_shifts
    where status = 'OPEN' order by opened_at desc limit 1
    for update;
  if not found then
    raise exception 'no_open_shift' using errcode = 'P0001';
  end if;

  select coalesce(sum(p.amount - s.refund_amount), 0)
    into v_cash_sales
    from public.payments p
    join public.sales s on s.id = p.sale_id
   where p.method = 'CASH' and p.created_at >= v_shift.opened_at;
  if v_cash_sales < 0 then
    v_cash_sales := 0;
  end if;
  v_expected := v_shift.opening_cash + v_cash_sales;

  update public.cash_shifts
     set status = 'CLOSED',
         expected_cash = v_expected,
         actual_cash = p_actual_cash,
         variance = p_actual_cash - v_expected,
         note = nullif(trim(coalesce(p_note, '')), ''),
         closed_at = now(),
         closed_by = auth.uid()
   where id = v_shift.id;

  insert into public.audit_events (entity, entity_id, action, detail,
                                   created_by)
  values ('cash_shift', v_shift.id::text, 'CLOSE',
          jsonb_build_object('expected', v_expected,
                             'actual', p_actual_cash,
                             'variance', p_actual_cash - v_expected),
          auth.uid());

  return (select jsonb_build_object(
    'shift_id', id, 'opening_cash', opening_cash,
    'expected_cash', expected_cash, 'actual_cash', actual_cash,
    'variance', variance, 'closed_at', closed_at)
    from public.cash_shifts where id = v_shift.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- S05-06/07: laporan deskriptif satu rentang tanggal (WIB).
-- Tidak ada forecast; "biaya bahan" = HPP resep aktif x qty terjual
-- (estimasi dari unit_cost terkini, dilabeli jujur).
-- ---------------------------------------------------------------------------
create or replace function public.pos_reports(
  p_from date default null,
  p_to date default null
)
returns jsonb
language sql stable security definer set search_path = public as $$
with bounds as (
  select
    coalesce(p_from,
      (now() at time zone 'Asia/Jakarta')::date - interval '6 days')::date
      as d_from,
    coalesce(p_to,
      (now() at time zone 'Asia/Jakarta')::date)::date as d_to
),
sales_in as (
  select s.*
  from public.sales s, bounds b
  where (s.created_at at time zone 'Asia/Jakarta')::date
          between b.d_from and b.d_to
),
trend as (
  select to_char((s.created_at at time zone 'Asia/Jakarta')::date,
                 'YYYY-MM-DD') as day,
         coalesce(sum(s.total - s.refund_amount)
           filter (where s.status <> 'REFUNDED'), 0)::bigint as revenue,
         count(*) filter (where s.status <> 'REFUNDED')::bigint as tx
  from sales_in s
  group by 1 order by 1
),
top_products as (
  select si.product_name as name,
         sum(si.qty)::bigint as qty,
         sum(si.unit_price * si.qty)::bigint as revenue
  from sale_items si
  join sales_in s on s.id = si.sale_id
  where s.status <> 'REFUNDED'
  group by 1 order by sum(si.qty) desc limit 10
),
-- Biaya bahan (estimasi): HPP versi resep aktif x qty terjual.
hpp_cost as (
  select coalesce(sum(si.qty * hpp.cost), 0)::bigint as cost
  from sale_items si
  join sales_in s on s.id = si.sale_id
  left join lateral (
    select coalesce(sum(ri.qty * ing.unit_cost), 0) as cost
      from public.recipe_versions rv
      join public.recipe_items ri on ri.recipe_version_id = rv.id
      join public.ingredients ing on ing.id = ri.ingredient_id
     where rv.product_id = si.product_id and rv.is_active
  ) hpp on true
  where s.status <> 'REFUNDED'
),
exp_agg as (
  select
    coalesce(sum(amount) filter (where kind = 'ACTUAL'),
             0)::bigint as actual_total,
    coalesce(sum(amount) filter (where kind = 'ESTIMATED'),
             0)::bigint as estimated_total,
    coalesce(sum(amount) filter (
      where kind = 'ACTUAL' and expense_date between b.d_from and b.d_to),
      0)::bigint as actual_period,
    coalesce(sum(amount) filter (
      where kind = 'ESTIMATED' and expense_date between b.d_from and b.d_to),
      0)::bigint as estimated_period
  from public.expenses, bounds b
),
exp_by_type as (
  select type,
         coalesce(sum(amount) filter (where kind = 'ACTUAL'),
                  0)::bigint as actual_amount,
         coalesce(sum(amount) filter (where kind = 'ESTIMATED'),
                  0)::bigint as estimated_amount
  from public.expenses
  group by 1 order by 1
),
alloc as (
  select coalesce(sum(amount), 0)::bigint as allocated
  from public.cost_allocations
)
select jsonb_build_object(
  'd_from', (select d_from from bounds),
  'd_to', (select d_to from bounds),
  'net_sales', coalesce((select sum(total - refund_amount)
    from sales_in where status <> 'REFUNDED'), 0)::bigint,
  'refunds', coalesce((select sum(refund_amount)
    from sales_in), 0)::bigint,
  'transactions', (select count(*) from sales_in
    where status <> 'REFUNDED')::bigint,
  'trend', (select coalesce(jsonb_agg(t), '[]'::jsonb) from trend t),
  'top_products', (select coalesce(jsonb_agg(p), '[]'::jsonb)
                   from top_products p),
  'hpp_ingredient_cost', (select cost from hpp_cost),
  'expenses_actual', (select actual_total from exp_agg),
  'expenses_estimated', (select estimated_total from exp_agg),
  'expenses_actual_period', (select actual_period from exp_agg),
  'expenses_estimated_period', (select estimated_period from exp_agg),
  'expenses_by_type', (select coalesce(jsonb_agg(e), '[]'::jsonb)
                       from exp_by_type e),
  'allocated_total', (select allocated from alloc)
);
$$;

-- ---------------------------------------------------------------------------
-- Grants: operator (authenticated) saja; publik/anon tertutup.
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'exp_save(bigint, text, text, integer, text, date, text)',
    'energy_save_estimate(text, numeric, numeric, numeric, numeric, '
      'integer, numeric, numeric, integer, text)',
    'cost_allocate(bigint, text, integer)',
    'cash_shift_status()',
    'cash_shift_open(integer)',
    'cash_shift_close(integer, text)',
    'pos_reports(date, date)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

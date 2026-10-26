-- 0010_inventory.sql
-- Sprint 04 (S04-01…S04-09): master bahan + satuan dasar, ledger mutasi
-- append-only, pembelian/penerimaan, resep versi + yield, produksi batch,
-- HPP per porsi, batas minimum, waste.
--
-- Kebijakan posting (FR-17/S04-06), TANPA pengurangan ganda:
--   * make-to-order (products.stock_mode = 'RECIPE'): pemakaian bahan
--     diposting TEPAT SEKALI saat sale final, lewat trigger
--     AFTER INSERT ON payments di transaksi checkout yang sama (atomic;
--     path idempoten tidak memasukkan payments baru jadi tidak dobel).
--   * pre-made per batch ('BATCH', gorengan): bahan dipotong sekali saat
--     produksi batch; penjualan TIDAK memotong lagi.
--   * tanpa resep aktif: TIDAK ada klaim stok; UI menampilkan
--     "resep belum ada" (S04-07).
--   * refund TIDAK mengembalikan stok otomatis; koreksi dicatat eksplisit
--     dengan alasan (ADJUSTMENT/WASTE) — kebijakan audit.
-- Tanpa AI/prediksi apa pun (larangan scope).

-- ---------------------------------------------------------------------------
-- S04-01: master bahan. Satuan dasar hanya g/ml/pcs; kg & liter dikonversi
-- di server (inv_to_base). Qty desimal presisi.
-- ---------------------------------------------------------------------------
create table if not exists public.ingredients (
  id bigint generated always as identity primary key,
  name text not null unique,
  base_unit text not null check (base_unit in ('g', 'ml', 'pcs')),
  balance numeric(14, 3) not null default 0,
  reorder_level numeric(14, 3) not null default 0 check (reorder_level >= 0),
  -- Biaya per satuan dasar (Rp), diperbarui saat pembelian diterima.
  unit_cost integer not null default 0 check (unit_cost >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- S04-05: ledger mutasi. Append-only: trigger menolak UPDATE/DELETE,
-- RLS hanya SELECT (tulisan hanya lewat fungsi definer).
-- ---------------------------------------------------------------------------
create table if not exists public.stock_movements (
  id bigint generated always as identity primary key,
  ingredient_id bigint not null references public.ingredients (id),
  qty_delta numeric(14, 3) not null check (qty_delta <> 0),
  balance_after numeric(14, 3) not null,
  source text not null
    check (source in ('PURCHASE', 'RECIPE', 'PRODUCTION', 'WASTE', 'ADJUSTMENT')),
  reason text not null,
  ref text,                                -- sale_id / batch:<id> / po:<id>
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create index if not exists stock_movements_ingredient_idx
  on public.stock_movements (ingredient_id, id desc);
create index if not exists stock_movements_ref_idx
  on public.stock_movements (source, ref);

create or replace function public.stock_movements_immutable()
returns trigger
language plpgsql as $$
begin
  raise exception 'ledger_append_only'
    using errcode = 'P0001',
          hint = 'Mutasi stok hanya ditambah; koreksi lewat mutasi baru.';
end;
$$;

drop trigger if exists trg_stock_movements_immutable on public.stock_movements;
create trigger trg_stock_movements_immutable
  before update or delete on public.stock_movements
  for each row execute function public.stock_movements_immutable();

-- ---------------------------------------------------------------------------
-- S04-03: pembelian/penerimaan. ORDERED belum menambah saldo; RECEIVED
-- menambah tepat sekali (guard status).
-- ---------------------------------------------------------------------------
create table if not exists public.purchases (
  id bigint generated always as identity primary key,
  supplier text,
  purchased_at date not null default current_date,
  status text not null default 'RECEIVED'
    check (status in ('ORDERED', 'RECEIVED')),
  total integer not null default 0 check (total >= 0),
  received_at timestamptz,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create table if not exists public.purchase_items (
  id bigint generated always as identity primary key,
  purchase_id bigint not null references public.purchases (id) on delete cascade,
  ingredient_id bigint not null references public.ingredients (id),
  qty numeric(14, 3) not null check (qty > 0),  -- dalam satuan dasar
  unit_cost integer not null check (unit_cost >= 0), -- Rp per satuan dasar
  total integer not null check (total >= 0)
);

create index if not exists purchase_items_purchase_idx
  on public.purchase_items (purchase_id);

-- ---------------------------------------------------------------------------
-- S04-04/05: resep berbasis versi + yield per batch. Versi lama tidak
-- dihapus (riwayat biaya bisa ditelusuri).
-- ---------------------------------------------------------------------------
create table if not exists public.recipe_versions (
  id bigint generated always as identity primary key,
  product_id bigint not null references public.products (id),
  version integer not null check (version > 0),
  yield_qty numeric(14, 3) not null default 1 check (yield_qty > 0),
  is_active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  unique (product_id, version)
);

create table if not exists public.recipe_items (
  id bigint generated always as identity primary key,
  recipe_version_id bigint not null
    references public.recipe_versions (id) on delete cascade,
  ingredient_id bigint not null references public.ingredients (id),
  qty numeric(14, 3) not null check (qty > 0), -- kebutuhan per yield batch
  unique (recipe_version_id, ingredient_id)
);

create index if not exists recipe_versions_product_idx
  on public.recipe_versions (product_id, is_active);

-- Mode pemotongan stok per produk (S04-07).
alter table public.products
  add column if not exists stock_mode text not null default 'RECIPE';
alter table public.products drop constraint if exists products_stock_mode_check;
alter table public.products
  add constraint products_stock_mode_check
  check (stock_mode in ('RECIPE', 'BATCH'));

-- ---------------------------------------------------------------------------
-- S04-07: produksi batch (gorengan) — bahan dipotong sekali per batch.
-- ---------------------------------------------------------------------------
create table if not exists public.production_batches (
  id bigint generated always as identity primary key,
  product_id bigint not null references public.products (id),
  recipe_version_id bigint not null references public.recipe_versions (id),
  qty_produced numeric(14, 3) not null check (qty_produced > 0),
  note text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- RLS: operator hanya MEMBACA; semua tulisan lewat fungsi definer di bawah
-- agar saldo dan ledger selalu sinkron.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'ingredients', 'stock_movements', 'purchases', 'purchase_items',
    'recipe_versions', 'recipe_items', 'production_batches'
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
-- Helper konversi satuan input -> satuan dasar (Kg↔g, L↔ml, pcs).
-- ---------------------------------------------------------------------------
create or replace function public.inv_to_base(
  p_qty numeric,
  p_unit text,
  p_base_unit text
)
returns numeric
language plpgsql immutable set search_path = public as $$
declare
  v_unit text := lower(trim(coalesce(p_unit, '')));
  v_qty numeric := p_qty;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'invalid_qty' using errcode = 'P0001';
  end if;
  if v_unit in ('kg', 'kilogram') then
    v_qty := p_qty * 1000; v_unit := 'g';
  elsif v_unit in ('g', 'gram') then
    v_unit := 'g';
  elsif v_unit in ('l', 'liter', 'litre') then
    v_qty := p_qty * 1000; v_unit := 'ml';
  elsif v_unit = 'ml' then
    v_unit := 'ml';
  elsif v_unit in ('pcs', 'biji', 'butir', 'unit') then
    v_unit := 'pcs';
  else
    raise exception 'invalid_unit' using errcode = 'P0001';
  end if;
  if v_unit <> p_base_unit then
    raise exception 'unit_mismatch'
      using errcode = 'P0001',
            hint = 'Satuan harus sejenis dengan satuan dasar bahan.';
  end if;
  return round(v_qty, 3);
end;
$$;

-- ---------------------------------------------------------------------------
-- Helper inti: satu baris mutasi + saldo. Satu-satunya jalur tulis saldo.
-- ---------------------------------------------------------------------------
create or replace function public.inv_post_movement(
  p_ingredient_id bigint,
  p_qty_delta numeric,
  p_source text,
  p_reason text,
  p_ref text
)
returns numeric
language plpgsql security definer set search_path = public as $$
declare
  v_name text;
  v_unit text;
  v_bal numeric;
begin
  select name, base_unit, balance into v_name, v_unit, v_bal
  from public.ingredients where id = p_ingredient_id for update;
  if not found then
    raise exception 'ingredient_not_found' using errcode = 'P0001';
  end if;
  if p_qty_delta = 0 then
    raise exception 'invalid_qty_delta' using errcode = 'P0001';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'missing_reason'
      using errcode = 'P0001', hint = 'Setiap mutasi stok wajib beralasan.';
  end if;

  update public.ingredients
     set balance = balance + p_qty_delta,
         updated_at = now()
   where id = p_ingredient_id
  returning balance into v_bal;

  if v_bal < 0 then
    raise exception 'insufficient_stock: % (kurang % %)',
      v_name, abs(round(v_bal, 3)), v_unit using errcode = 'P0001';
  end if;

  insert into public.stock_movements
    (ingredient_id, qty_delta, balance_after, source, reason, ref, created_by)
  values
    (p_ingredient_id, p_qty_delta, v_bal, p_source, trim(p_reason),
     p_ref, auth.uid());
  return v_bal;
end;
$$;

-- ---------------------------------------------------------------------------
-- Posting pemakaian sale final — TEPAT SEKALI per sale.
-- Dipanggil trigger AFTER INSERT ON payments (payments hanya diinsert saat
-- checkout; jalur idempoten tidak menginsert payments baru).
-- ---------------------------------------------------------------------------
create or replace function public.inv_post_sale_usage(p_sale_id bigint)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_receipt text;
  v_row record;
  v_short text := '';
begin
  -- Penjaga defensif: satu sale = satu set mutasi RECIPE.
  if exists (select 1 from public.stock_movements
             where source = 'RECIPE' and ref = p_sale_id::text) then
    return;
  end if;

  select receipt_no into v_receipt from public.sales where id = p_sale_id;
  if v_receipt is null then
    raise exception 'sale_not_found' using errcode = 'P0001';
  end if;

  -- Hanya produk make-to-order ('RECIPE') dengan resep aktif; BATCH dan
  -- tanpa resep tidak diklaim di sini.
  for v_row in
    select i.id as ingredient_id, i.name, i.balance, i.base_unit,
           sum(ri.qty * si.qty / rv.yield_qty) as need
      from public.sale_items si
      join public.products p on p.id = si.product_id
      join public.recipe_versions rv
        on rv.product_id = p.id and rv.is_active
      join public.recipe_items ri on ri.recipe_version_id = rv.id
      join public.ingredients i on i.id = ri.ingredient_id
     where si.sale_id = p_sale_id
       and p.stock_mode = 'RECIPE'
     group by i.id, i.name, i.balance, i.base_unit
  loop
    if v_row.balance < v_row.need then
      v_short := v_short || case when v_short = '' then '' else ', ' end
                 || v_row.name;
    end if;
  end loop;

  if v_short <> '' then
    raise exception 'insufficient_stock: %', v_short
      using errcode = 'P0001',
            hint = 'Terima pembelian atau koreksi stok dengan alasan, lalu ulangi pembayaran.';
  end if;

  for v_row in
    select i.id as ingredient_id,
           sum(ri.qty * si.qty / rv.yield_qty) as need
      from public.sale_items si
      join public.products p on p.id = si.product_id
      join public.recipe_versions rv
        on rv.product_id = p.id and rv.is_active
      join public.recipe_items ri on ri.recipe_version_id = rv.id
      join public.ingredients i on i.id = ri.ingredient_id
     where si.sale_id = p_sale_id
       and p.stock_mode = 'RECIPE'
     group by i.id
  loop
    perform public.inv_post_movement(
      v_row.ingredient_id, round(-v_row.need, 3), 'RECIPE',
      'Pemakaian resep ' || v_receipt, p_sale_id::text);
  end loop;
end;
$$;

create or replace function public.inv_sale_stock_after_payment()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.inv_post_sale_usage(NEW.sale_id);
  return NEW;
end;
$$;

drop trigger if exists trg_inv_post_sale_usage on public.payments;
create trigger trg_inv_post_sale_usage
  after insert on public.payments
  for each row execute function public.inv_sale_stock_after_payment();

-- ---------------------------------------------------------------------------
-- S04-02: CRUD bahan + koreksi stok/waste beralasan.
-- ---------------------------------------------------------------------------
create or replace function public.inv_save_ingredient(
  p_id bigint default null,
  p_name text default null,
  p_base_unit text default null,
  p_reorder_level numeric default 0,
  p_unit_cost integer default 0
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_name text := trim(coalesce(p_name, ''));
  v_unit text := lower(trim(coalesce(p_base_unit, '')));
  v_id bigint;
begin
  if length(v_name) < 2 or length(v_name) > 60 then
    raise exception 'invalid_name' using errcode = 'P0001';
  end if;
  if v_unit not in ('g', 'ml', 'pcs') then
    raise exception 'invalid_base_unit' using errcode = 'P0001';
  end if;
  if p_reorder_level is null or p_reorder_level < 0 then
    raise exception 'invalid_reorder_level' using errcode = 'P0001';
  end if;
  if p_unit_cost is null or p_unit_cost < 0 then
    raise exception 'invalid_unit_cost' using errcode = 'P0001';
  end if;

  if p_id is null then
    insert into public.ingredients (name, base_unit, reorder_level, unit_cost)
    values (v_name, v_unit, p_reorder_level, p_unit_cost)
    returning id into v_id;
    insert into public.audit_events (entity, entity_id, action, detail, created_by)
    values ('ingredient', v_id::text, 'CREATE',
            jsonb_build_object('name', v_name, 'base_unit', v_unit),
            auth.uid());
  else
    update public.ingredients
       set name = v_name,
           reorder_level = p_reorder_level,
           unit_cost = p_unit_cost,
           updated_at = now()
     where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'ingredient_not_found' using errcode = 'P0001';
    end if;
    -- Satuan dasar tidak bisa berubah setelah bahan dibuat (konversi histori).
    if exists (select 1 from public.ingredients
               where id = p_id and base_unit <> v_unit) then
      raise exception 'base_unit_locked' using errcode = 'P0001';
    end if;
    insert into public.audit_events (entity, entity_id, action, detail, created_by)
    values ('ingredient', v_id::text, 'UPDATE',
            jsonb_build_object('name', v_name, 'reorder_level', p_reorder_level,
                               'unit_cost', p_unit_cost),
            auth.uid());
  end if;

  return (select jsonb_build_object(
    'id', id, 'name', name, 'base_unit', base_unit, 'balance', balance,
    'reorder_level', reorder_level, 'unit_cost', unit_cost)
    from public.ingredients where id = v_id);
end;
$$;

create or replace function public.inv_adjust_stock(
  p_ingredient_id bigint,
  p_qty numeric,
  p_unit text default null,
  p_reason text default null,
  p_source text default 'ADJUSTMENT'
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_base text;
  v_qty_base numeric;
  v_delta numeric;
  v_bal numeric;
begin
  if p_source not in ('ADJUSTMENT', 'WASTE') then
    raise exception 'invalid_source' using errcode = 'P0001';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'missing_reason' using errcode = 'P0001';
  end if;

  select base_unit into v_base
  from public.ingredients where id = p_ingredient_id for update;
  if not found then
    raise exception 'ingredient_not_found' using errcode = 'P0001';
  end if;

  v_qty_base := public.inv_to_base(p_qty, v_base, v_base);
  -- Waste selalu pengurangan; koreksi boleh naik/turun sesuai tanda qty.
  v_delta := case when p_source = 'WASTE' then -abs(v_qty_base)
                  else p_qty end;

  v_bal := public.inv_post_movement(
    p_ingredient_id, round(v_delta, 3), p_source,
    case when p_source = 'WASTE' then 'Waste: ' || trim(p_reason)
         else 'Koreksi: ' || trim(p_reason) end,
    null);

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('ingredient', p_ingredient_id::text, p_source,
          jsonb_build_object('qty_delta', v_delta, 'reason', trim(p_reason),
                             'balance_after', v_bal),
          auth.uid());

  return (select jsonb_build_object(
    'id', id, 'name', name, 'base_unit', base_unit, 'balance', balance,
    'reorder_level', reorder_level, 'unit_cost', unit_cost)
    from public.ingredients where id = p_ingredient_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- S04-03: pembelian. items: [{ingredient_id, qty, unit, total_price}].
-- Saldo & unit_cost (harga terakhir per satuan dasar) bertambah sekali
-- saat RECEIVED; ORDERED menyusul lewat inv_receive_purchase.
-- ---------------------------------------------------------------------------
create or replace function public.inv_create_purchase(
  p_supplier text default null,
  p_items jsonb default null,
  p_purchased_at date default null,
  p_status text default 'RECEIVED'
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_purchase_id bigint;
  v_total integer := 0;
  v_item jsonb;
  v_pid bigint;
  v_qty_base numeric;
  v_price numeric;
  v_cost integer;
  v_line_total integer;
  v_base text;
  v_received boolean := false;
  v_lines jsonb := '[]'::jsonb;
begin
  if p_status not in ('ORDERED', 'RECEIVED') then
    raise exception 'invalid_status' using errcode = 'P0001';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 50 then
    raise exception 'invalid_items' using errcode = 'P0001';
  end if;

  insert into public.purchases (supplier, purchased_at, status, created_by)
  values (nullif(trim(coalesce(p_supplier, '')), ''),
          coalesce(p_purchased_at, current_date), p_status, auth.uid())
  returning id into v_purchase_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := (v_item ->> 'ingredient_id')::bigint;
    select base_unit into v_base
    from public.ingredients where id = v_pid for update;
    if not found then
      raise exception 'ingredient_not_found' using errcode = 'P0001';
    end if;

    v_qty_base := public.inv_to_base(
      (v_item ->> 'qty')::numeric, v_item ->> 'unit', v_base);
    v_price := (v_item ->> 'total_price')::numeric;
    if v_price is null or v_price < 0 then
      raise exception 'invalid_price' using errcode = 'P0001';
    end if;
    v_cost := round((v_price / v_qty_base)::numeric)::integer;
    v_line_total := round(v_price)::integer;
    v_total := v_total + v_line_total;

    insert into public.purchase_items
      (purchase_id, ingredient_id, qty, unit_cost, total)
    values (v_purchase_id, v_pid, v_qty_base, v_cost, v_line_total);

    if p_status = 'RECEIVED' then
      perform public.inv_post_movement(
        v_pid, v_qty_base, 'PURCHASE',
        'Pembelian po:' || v_purchase_id, 'po:' || v_purchase_id);
      update public.ingredients set unit_cost = v_cost, updated_at = now()
       where id = v_pid;
      v_received := true;
    end if;

    v_lines := v_lines || jsonb_build_object(
      'ingredient_id', v_pid, 'qty', v_qty_base, 'unit_cost', v_cost,
      'total', v_line_total);
  end loop;

  update public.purchases
     set total = v_total,
         received_at = case when v_received then now() end
   where id = v_purchase_id;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('purchase', v_purchase_id::text, 'CREATE',
          jsonb_build_object('status', p_status, 'total', v_total),
          auth.uid());

  return jsonb_build_object(
    'purchase_id', v_purchase_id, 'status', p_status, 'total', v_total,
    'items', v_lines);
end;
$$;

create or replace function public.inv_receive_purchase(p_purchase_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
  v_item record;
begin
  select status into v_status
  from public.purchases where id = p_purchase_id for update;
  if not found then
    raise exception 'purchase_not_found' using errcode = 'P0001';
  end if;
  if v_status <> 'ORDERED' then
    raise exception 'purchase_already_received' using errcode = 'P0001';
  end if;

  for v_item in
    select pi.ingredient_id, pi.qty, pi.unit_cost
      from public.purchase_items pi where pi.purchase_id = p_purchase_id
  loop
    perform public.inv_post_movement(
      v_item.ingredient_id, v_item.qty, 'PURCHASE',
      'Penerimaan po:' || p_purchase_id, 'po:' || p_purchase_id);
    update public.ingredients
       set unit_cost = v_item.unit_cost, updated_at = now()
     where id = v_item.ingredient_id;
  end loop;

  update public.purchases
     set status = 'RECEIVED', received_at = now()
   where id = p_purchase_id;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('purchase', p_purchase_id::text, 'RECEIVE', '{}'::jsonb, auth.uid());

  return (select jsonb_build_object(
    'purchase_id', id, 'status', status, 'total', total,
    'received_at', received_at)
    from public.purchases where id = p_purchase_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- S04-04: simpan resep sebagai VERSI BARU (versi lama tetap untuk jejak HPP).
-- ---------------------------------------------------------------------------
create or replace function public.inv_save_recipe(
  p_product_id bigint,
  p_yield_qty numeric default 1,
  p_items jsonb default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_version_id bigint;
  v_version integer;
  v_item jsonb;
  v_exists boolean;
begin
  select true into v_exists from public.products
  where id = p_product_id and archived_at is null;
  if not coalesce(v_exists, false) then
    raise exception 'product_not_found' using errcode = 'P0001';
  end if;
  if p_yield_qty is null or p_yield_qty <= 0 or p_yield_qty > 10000 then
    raise exception 'invalid_yield' using errcode = 'P0001';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 50 then
    raise exception 'invalid_items' using errcode = 'P0001';
  end if;

  update public.recipe_versions set is_active = false
   where product_id = p_product_id and is_active;

  select coalesce(max(version), 0) + 1 into v_version
  from public.recipe_versions where product_id = p_product_id;

  insert into public.recipe_versions
    (product_id, version, yield_qty, is_active, created_by)
  values (p_product_id, v_version, p_yield_qty, true, auth.uid())
  returning id into v_version_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    if not exists (select 1 from public.ingredients
                   where id = (v_item ->> 'ingredient_id')::bigint) then
      raise exception 'ingredient_not_found' using errcode = 'P0001';
    end if;
    if (v_item ->> 'qty')::numeric is null
       or (v_item ->> 'qty')::numeric <= 0 then
      raise exception 'invalid_qty' using errcode = 'P0001';
    end if;
    insert into public.recipe_items (recipe_version_id, ingredient_id, qty)
    values (v_version_id, (v_item ->> 'ingredient_id')::bigint,
            (v_item ->> 'qty')::numeric);
  end loop;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('recipe', p_product_id::text, 'SAVE_VERSION',
          jsonb_build_object('version', v_version, 'yield_qty', p_yield_qty),
          auth.uid());

  return public.inv_hpp(p_product_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- S04-04: HPP per porsi dari resep aktif × unit_cost.
-- ---------------------------------------------------------------------------
create or replace function public.inv_hpp(p_product_id bigint)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_vid bigint;
  v_version integer;
  v_yield numeric;
  v_items jsonb;
  v_hpp numeric;
begin
  select id, version, yield_qty into v_vid, v_version, v_yield
  from public.recipe_versions
  where product_id = p_product_id and is_active;

  if v_vid is null then
    return jsonb_build_object('product_id', p_product_id,
                              'has_recipe', false);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'ingredient_id', i.id, 'name', i.name, 'base_unit', i.base_unit,
           'qty', ri.qty, 'unit_cost', i.unit_cost,
           'cost', round(ri.qty * i.unit_cost)::bigint,
           'balance', i.balance) order by i.name), '[]'::jsonb)
    into v_items
  from public.recipe_items ri
  join public.ingredients i on i.id = ri.ingredient_id
  where ri.recipe_version_id = v_vid;

  select round(coalesce(sum((r.item ->> 'qty')::numeric
                    * (r.item ->> 'unit_cost')::numeric), 0) / v_yield, 2)
    into v_hpp
  from jsonb_array_elements(v_items) r(item);

  return jsonb_build_object(
    'product_id', p_product_id, 'has_recipe', true,
    'version', v_version, 'yield_qty', v_yield,
    'items', v_items, 'hpp_per_portion', v_hpp);
end;
$$;

-- ---------------------------------------------------------------------------
-- S04-07: produksi batch (gorengan). Bahan dipotong sekali di sini;
-- penjualan produk BATCH tidak memotong lagi (lihat inv_post_sale_usage).
-- ---------------------------------------------------------------------------
create or replace function public.inv_produce_batch(
  p_product_id bigint,
  p_qty_produced numeric default null,
  p_note text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_vid bigint;
  v_yield numeric;
  v_batch_id bigint;
  v_row record;
  v_short text := '';
  v_factor numeric;
begin
  select id, yield_qty into v_vid, v_yield
  from public.recipe_versions
  where product_id = p_product_id and is_active;
  if v_vid is null then
    raise exception 'recipe_missing'
      using errcode = 'P0001',
            hint = 'Buat resep aktif sebelum mencatat produksi batch.';
  end if;
  if p_qty_produced is null or p_qty_produced <= 0 then
    raise exception 'invalid_qty' using errcode = 'P0001';
  end if;

  v_factor := p_qty_produced / v_yield;

  for v_row in
    select i.id as ingredient_id, i.name, i.balance,
           ri.qty * v_factor as need
      from public.recipe_items ri
      join public.ingredients i on i.id = ri.ingredient_id
     where ri.recipe_version_id = v_vid
  loop
    if v_row.balance < v_row.need then
      v_short := v_short || case when v_short = '' then '' else ', ' end
                 || v_row.name;
    end if;
  end loop;
  if v_short <> '' then
    raise exception 'insufficient_stock: %', v_short
      using errcode = 'P0001',
            hint = 'Terima pembelian atau koreksi stok dengan alasan dulu.';
  end if;

  insert into public.production_batches
    (product_id, recipe_version_id, qty_produced, note, created_by)
  values (p_product_id, v_vid, p_qty_produced,
          nullif(trim(coalesce(p_note, '')), ''), auth.uid())
  returning id into v_batch_id;

  for v_row in
    select i.id as ingredient_id, ri.qty * v_factor as need
      from public.recipe_items ri
      join public.ingredients i on i.id = ri.ingredient_id
     where ri.recipe_version_id = v_vid
  loop
    perform public.inv_post_movement(
      v_row.ingredient_id, round(-v_row.need, 3), 'PRODUCTION',
      'Produksi batch ' || coalesce(nullif(trim(p_note), ''),
          v_batch_id::text), 'batch:' || v_batch_id);
  end loop;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('production_batch', v_batch_id::text, 'CREATE',
          jsonb_build_object('product_id', p_product_id,
                             'qty_produced', p_qty_produced),
          auth.uid());

  return jsonb_build_object(
    'batch_id', v_batch_id, 'product_id', p_product_id,
    'recipe_version_id', v_vid, 'qty_produced', p_qty_produced);
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants: tulisan hanya operator (authenticated); publik/anon tertutup.
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'inv_save_ingredient(bigint, text, text, numeric, integer)',
    'inv_adjust_stock(bigint, numeric, text, text, text)',
    'inv_create_purchase(text, jsonb, date, text)',
    'inv_receive_purchase(bigint)',
    'inv_save_recipe(bigint, numeric, jsonb)',
    'inv_produce_batch(bigint, numeric, text)',
    'inv_hpp(bigint)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;

  -- Helper internal: hanya dipanggil fungsi definer lain.
  foreach f in array array[
    'inv_to_base(numeric, text, text)',
    'inv_post_movement(bigint, numeric, text, text, text)',
    'inv_post_sale_usage(bigint)',
    'inv_sale_stock_after_payment()',
    'stock_movements_immutable()'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

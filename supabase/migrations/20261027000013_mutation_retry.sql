-- Retry refund dan koreksi/waste: satu key = satu payload dan satu efek committed.
create table public.mutation_requests (
  operation text not null check (operation in ('pos_refund', 'inv_adjust_stock')),
  idempotency_key text not null check (length(idempotency_key) between 8 and 128),
  request jsonb not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (operation, idempotency_key)
);
alter table public.mutation_requests enable row level security;
revoke all on public.mutation_requests from public, anon, authenticated;

-- Simpan validasi/ledger lama, tetapi jangan sisakan RPC tanpa deduplikasi.
alter function public.pos_refund(bigint, integer, text) rename to pos_refund_once;
revoke all on function public.pos_refund_once(bigint, integer, text)
  from public, anon, authenticated;
alter function public.inv_adjust_stock(bigint, numeric, text, text, text)
  rename to inv_adjust_stock_once;
revoke all on function public.inv_adjust_stock_once(bigint, numeric, text, text, text)
  from public, anon, authenticated;

-- Koreksi bertanda minus harus memvalidasi magnitudo, bukan menolak tandanya.
create or replace function public.inv_adjust_stock_once(
  p_ingredient_id bigint, p_qty numeric, p_unit text default null,
  p_reason text default null, p_source text default 'ADJUSTMENT'
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
  select base_unit into v_base from public.ingredients
   where id = p_ingredient_id for update;
  if not found then
    raise exception 'ingredient_not_found' using errcode = 'P0001';
  end if;
  v_qty_base := public.inv_to_base(abs(p_qty), coalesce(p_unit, v_base), v_base);
  if p_source = 'WASTE' and p_qty < 0 then
    raise exception 'invalid_qty' using errcode = 'P0001';
  end if;
  v_delta := case when p_source = 'WASTE' then -v_qty_base
                  else sign(p_qty) * v_qty_base end;
  v_bal := public.inv_post_movement(
    p_ingredient_id, round(v_delta, 3), p_source,
    case when p_source = 'WASTE' then 'Waste: ' || trim(p_reason)
         else 'Koreksi: ' || trim(p_reason) end, null);
  insert into public.audit_events(entity, entity_id, action, detail, created_by)
  values ('ingredient', p_ingredient_id::text, p_source,
          jsonb_build_object('qty_delta', v_delta, 'reason', trim(p_reason),
                             'balance_after', v_bal), auth.uid());
  return (select jsonb_build_object(
    'id', id, 'name', name, 'base_unit', base_unit, 'balance', balance,
    'reorder_level', reorder_level, 'unit_cost', unit_cost)
    from public.ingredients where id = p_ingredient_id);
end;
$$;

create function public.pos_refund(
  p_sale_id bigint,
  p_amount integer,
  p_reason text,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_request jsonb := jsonb_build_object(
    'sale_id', p_sale_id, 'amount', p_amount, 'reason', trim(p_reason));
  v_existing public.mutation_requests%rowtype;
  v_response jsonb;
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8
     or length(p_idempotency_key) > 128 then
    raise exception 'missing_idempotency_key' using errcode = 'P0001';
  end if;
  -- Lock juga melindungi key yang belum memiliki baris; PK tetap jaminan akhir.
  perform pg_advisory_xact_lock(hashtextextended('pos_refund:' || p_idempotency_key, 0));
  select * into v_existing from public.mutation_requests
   where operation = 'pos_refund' and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request is distinct from v_request then
      raise exception 'idempotency_key_conflict' using errcode = 'P0001';
    end if;
    return v_existing.response || jsonb_build_object('idempotent_replay', true);
  end if;

  v_response := public.pos_refund_once(p_sale_id, p_amount, p_reason);
  insert into public.mutation_requests(operation, idempotency_key, request, response)
  values ('pos_refund', p_idempotency_key, v_request, v_response);
  return v_response || jsonb_build_object('idempotent_replay', false);
end;
$$;

create function public.inv_adjust_stock(
  p_ingredient_id bigint,
  p_qty numeric,
  p_unit text default null,
  p_reason text default null,
  p_source text default 'ADJUSTMENT',
  p_idempotency_key text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_request jsonb := jsonb_build_object(
    'ingredient_id', p_ingredient_id, 'qty', p_qty, 'unit', p_unit,
    'reason', trim(p_reason), 'source', p_source);
  v_existing public.mutation_requests%rowtype;
  v_response jsonb;
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8
     or length(p_idempotency_key) > 128 then
    raise exception 'missing_idempotency_key' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('inv_adjust_stock:' || p_idempotency_key, 0));
  select * into v_existing from public.mutation_requests
   where operation = 'inv_adjust_stock' and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request is distinct from v_request then
      raise exception 'idempotency_key_conflict' using errcode = 'P0001';
    end if;
    return v_existing.response || jsonb_build_object('idempotent_replay', true);
  end if;

  v_response := public.inv_adjust_stock_once(
    p_ingredient_id, p_qty, p_unit, p_reason, p_source);
  insert into public.mutation_requests(operation, idempotency_key, request, response)
  values ('inv_adjust_stock', p_idempotency_key, v_request, v_response);
  return v_response || jsonb_build_object('idempotent_replay', false);
end;
$$;

revoke all on function public.pos_refund(bigint, integer, text, text) from public, anon;
revoke all on function public.inv_adjust_stock(bigint, numeric, text, text, text, text)
  from public, anon;
grant execute on function public.pos_refund(bigint, integer, text, text) to authenticated;
grant execute on function public.inv_adjust_stock(bigint, numeric, text, text, text, text)
  to authenticated;
notify pgrst, 'reload schema';

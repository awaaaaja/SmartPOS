-- 0014_mutation_retry_rest.sql
-- S06 lanjutan: kunci idempotensi untuk mutasi yang masih menggandakan efek
-- saat retry (audit K06-01): pembelian, produksi batch, biaya aktual, estimasi
-- energi. Pola sama dengan 0013: key wajib 8-128 char, lock per key, request
-- identik -> respons tersimpan, payload berbeda -> ditolak, tanpa key -> gagal
-- tertutup. Data historis tidak disentuh.

-- ---------------------------------------------------------------------------
-- 1. Ruang lingkup tabel deduplikasi diperluas (constraint ditemukan dinamis
--    karena nama bawaan bisa berbeda antar Postgres).
-- ---------------------------------------------------------------------------
do $$
declare
  v_constraint text;
begin
  select conname into v_constraint
    from pg_constraint
   where conrelid = 'public.mutation_requests'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%operation%';
  if v_constraint is null then
    raise exception 'mutation_requests operation check not found';
  end if;
  execute format('alter table public.mutation_requests drop constraint %I',
                 v_constraint);
  alter table public.mutation_requests
    add constraint mutation_requests_operation_check
    check (operation in ('pos_refund', 'inv_adjust_stock',
                         'inv_create_purchase', 'inv_produce_batch',
                         'exp_save', 'energy_save_estimate'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. Helper bersama: validasi -> lock -> cache -> eksekusi -> simpan respons.
--    Dipanggil HANYA dari dalam fungsi SECURITY DEFINER lain (owner sama),
--    sehingga eksekusi dinamis tidak membuka akses ke anon/authenticated.
-- ---------------------------------------------------------------------------
create or replace function public.mutation_run_once(
  p_operation text,
  p_idempotency_key text,
  p_request jsonb,
  p_call text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_existing public.mutation_requests%rowtype;
  v_response jsonb;
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  if p_operation is null or p_idempotency_key is null
     or length(trim(p_idempotency_key)) < 8
     or length(p_idempotency_key) > 128 then
    raise exception 'missing_idempotency_key' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended(p_operation || ':' || p_idempotency_key, 0));
  select * into v_existing from public.mutation_requests
   where operation = p_operation and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request is distinct from p_request then
      raise exception 'idempotency_key_conflict' using errcode = 'P0001';
    end if;
    return v_existing.response || jsonb_build_object('idempotent_replay', true);
  end if;

  execute p_call into v_response;
  insert into public.mutation_requests(operation, idempotency_key, request, response)
  values (p_operation, p_idempotency_key, p_request, v_response);
  return v_response || jsonb_build_object('idempotent_replay', false);
end;
$$;

revoke all on function public.mutation_run_once(text, text, jsonb, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Simpan validasi/ledger lama, cabut grant (jalur lama tanpa key tertutup).
-- ---------------------------------------------------------------------------
alter function public.inv_create_purchase(text, jsonb, date, text)
  rename to inv_create_purchase_once;
revoke all on function public.inv_create_purchase_once(text, jsonb, date, text)
  from public, anon, authenticated;

alter function public.inv_produce_batch(bigint, numeric, text)
  rename to inv_produce_batch_once;
revoke all on function public.inv_produce_batch_once(bigint, numeric, text)
  from public, anon, authenticated;

alter function public.exp_save(bigint, text, text, integer, text, date, text)
  rename to exp_save_once;
revoke all on function public.exp_save_once(bigint, text, text, integer, text, date, text)
  from public, anon, authenticated;

alter function public.energy_save_estimate(
  text, numeric, numeric, numeric, numeric, integer, numeric, numeric, integer, text)
  rename to energy_save_estimate_once;
revoke all on function public.energy_save_estimate_once(
  text, numeric, numeric, numeric, numeric, integer, numeric, numeric, integer, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Wrapper bertanda tangan.
-- ---------------------------------------------------------------------------
create or replace function public.inv_create_purchase(
  p_supplier text default null,
  p_items jsonb default null,
  p_purchased_at date default null,
  p_status text default 'RECEIVED',
  p_idempotency_key text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return public.mutation_run_once(
    'inv_create_purchase', p_idempotency_key,
    jsonb_build_object('supplier', p_supplier, 'items', p_items,
                       'purchased_at', p_purchased_at, 'status', p_status),
    format('select public.inv_create_purchase_once(%L::text, %L::jsonb, %L::date, %L::text)',
           p_supplier, p_items, p_purchased_at, p_status));
end;
$$;

create or replace function public.inv_produce_batch(
  p_product_id bigint default null,
  p_qty_produced numeric default null,
  p_note text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return public.mutation_run_once(
    'inv_produce_batch', p_idempotency_key,
    jsonb_build_object('product_id', p_product_id,
                       'qty_produced', p_qty_produced, 'note', p_note),
    format('select public.inv_produce_batch_once(%L::bigint, %L::numeric, %L::text)',
           p_product_id, p_qty_produced, p_note));
end;
$$;

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
  p_note text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return public.mutation_run_once(
    'energy_save_estimate', p_idempotency_key,
    jsonb_build_object('kind', p_kind, 'watt', p_watt, 'hours', p_hours,
                       'load_factor', p_load_factor, 'tariff', p_tariff,
                       'refill_price', p_refill_price,
                       'effective_hours', p_effective_hours,
                       'batch_hours', p_batch_hours, 'portions', p_portions,
                       'note', p_note),
    format('select public.energy_save_estimate_once(%L::text, %L::numeric, %L::numeric, %L::numeric, %L::numeric, %L::integer, %L::numeric, %L::numeric, %L::integer, %L::text)',
           p_kind, p_watt, p_hours, p_load_factor, p_tariff, p_refill_price,
           p_effective_hours, p_batch_hours, p_portions, p_note));
end;
$$;

-- exp_save: jalur UPDATE (p_id terisi) idempoten secara alami (nilai yang sama
-- diterapkan dua kali = hasil sama) sehingga TANPA key dan TANPA cache — supaya
-- mengedit biaya setelah timeout tidak terkunci oleh permintaan lama. Jalur
-- CREATE tetap wajib key karena membuat baris baru.
create or replace function public.exp_save(
  p_id bigint default null,
  p_type text default null,
  p_description text default null,
  p_amount integer default null,
  p_kind text default 'ACTUAL',
  p_expense_date date default null,
  p_evidence_url text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_result jsonb;
  v_call text;
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  v_call := format(
    'select public.exp_save_once(%L::bigint, %L::text, %L::text, %L::integer, %L::text, %L::date, %L::text)',
    p_id, p_type, p_description, p_amount, p_kind, p_expense_date, p_evidence_url);
  if p_id is not null then
    execute v_call into v_result;
    return v_result;
  end if;
  return public.mutation_run_once(
    'exp_save', p_idempotency_key,
    jsonb_build_object('id', p_id, 'type', p_type,
                       'description', p_description, 'amount', p_amount,
                       'kind', p_kind, 'expense_date', p_expense_date,
                       'evidence_url', p_evidence_url),
    v_call);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Grants: tulisan hanya operator; helper internal tertutup.
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'inv_create_purchase(text, jsonb, date, text, text)',
    'inv_produce_batch(bigint, numeric, text, text)',
    'energy_save_estimate(text, numeric, numeric, numeric, numeric, integer, numeric, numeric, integer, text, text)',
    'exp_save(bigint, text, text, integer, text, date, text, text)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';

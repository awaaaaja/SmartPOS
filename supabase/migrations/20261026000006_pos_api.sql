-- 0006_pos_api.sql
-- Sprint 02 (S02-05/06/07/09): kalkulator uang HANYA di server.
-- Klien mengirim keranjang mentah; harga, pajak, layanan, total dihitung ulang
-- di sini. Integer Rupiah, pembulatan ROUND (setengah ke atas, deterministik).

-- ---------------------------------------------------------------------------
-- Helper: validasi & harga dasar satu baris keranjang.
-- ---------------------------------------------------------------------------
create or replace function public.pos_line_total(
  p_product_id bigint,
  p_qty integer,
  p_modifier_ids jsonb
)
returns integer
language plpgsql stable security definer set search_path = public as $$
declare
  v_price integer;
  v_name text;
  v_active boolean;
  v_archived timestamptz;
  v_delta integer := 0;
  v_mid bigint;
  v_max integer;
begin
  if p_qty is null or p_qty < 1 or p_qty > 99 then
    raise exception 'invalid_qty' using errcode = 'P0001';
  end if;

  select name, price, is_active, archived_at
    into v_name, v_price, v_active, v_archived
  from public.products where id = p_product_id;

  if v_name is null then
    raise exception 'product_not_found' using errcode = 'P0001';
  end if;
  if not v_active or v_archived is not null then
    raise exception 'product_unavailable: %', v_name using errcode = 'P0001';
  end if;

  for v_mid in
    select value::bigint from jsonb_array_elements(
      coalesce(p_modifier_ids, '[]'::jsonb)
    )
  loop
    select m.price_delta, pm.max_select into v_delta, v_max
    from public.modifiers m
    join public.product_modifiers pm
      on pm.modifier_id = m.id and pm.product_id = p_product_id
    where m.id = v_mid and m.is_active;

    if v_delta is null then
      raise exception 'modifier_not_allowed' using errcode = 'P0001';
    end if;
    if (
      select count(*) from jsonb_array_elements(
        coalesce(p_modifier_ids, '[]'::jsonb)
      ) where value::bigint = v_mid
    ) > v_max then
      raise exception 'modifier_max_exceeded' using errcode = 'P0001';
    end if;
    v_delta := 0;
  end loop;

  -- Hitung ulang delta (loop di atas memvalidasi; jumlahkan bersih).
  select coalesce(sum(m.price_delta), 0) into v_delta
  from jsonb_array_elements(coalesce(p_modifier_ids, '[]'::jsonb)) e
  join public.modifiers m on m.id = e.value::bigint
  join public.product_modifiers pm
    on pm.modifier_id = m.id and pm.product_id = p_product_id
  where m.is_active;

  return (v_price + v_delta) * p_qty;
end;
$$;

-- ---------------------------------------------------------------------------
-- Quote server (S02-05): klien TIDAK PERNAH mempercayai totalnya sendiri.
-- ---------------------------------------------------------------------------
create or replace function public.pos_quote(
  p_items jsonb,
  p_discount_pct numeric default 0
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_subtotal integer := 0;
  v_discount integer;
  v_tax_rate numeric;
  v_service_rate numeric;
  v_tax integer;
  v_service integer;
  v_total integer;
  v_item jsonb;
  v_line integer;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'empty_cart' using errcode = 'P0001';
  end if;
  if p_discount_pct is null or p_discount_pct < 0 or p_discount_pct > 100 then
    raise exception 'invalid_discount' using errcode = 'P0001';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_line := public.pos_line_total(
      (v_item ->> 'product_id')::bigint,
      (v_item ->> 'qty')::integer,
      v_item -> 'modifier_ids'
    );
    v_subtotal := v_subtotal + v_line;
  end loop;

  select coalesce(tax_rate, 0), coalesce(service_rate, 0)
    into v_tax_rate, v_service_rate
  from public.business_settings where id = 1;

  v_discount := round(v_subtotal * p_discount_pct / 100.0);
  v_tax := round((v_subtotal - v_discount) * v_tax_rate);
  v_service := round((v_subtotal - v_discount) * v_service_rate);
  v_total := v_subtotal - v_discount + v_tax + v_service;

  return jsonb_build_object(
    'subtotal', v_subtotal,
    'discount_amount', v_discount,
    'tax_amount', v_tax,
    'service_amount', v_service,
    'total', v_total
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Checkout atomik + idempoten (S02-07). Key sama = sale yang sama dikembalikan.
-- ---------------------------------------------------------------------------
create or replace function public.pos_checkout(
  p_items jsonb,
  p_method text,
  p_paid integer,
  p_dining_type text default 'TAKEAWAY',
  p_table_id bigint default null,
  p_discount_pct numeric default 0,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_existing public.sales%rowtype;
  v_q jsonb;
  v_sale_id bigint;
  v_receipt text;
  v_total integer;
  v_change integer;
  v_item jsonb;
  v_pid bigint;
  v_qty integer;
  v_name text;
  v_price integer;
  v_mods jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then
    raise exception 'missing_idempotency_key' using errcode = 'P0001';
  end if;
  if p_method not in ('CASH', 'TRANSFER', 'QRIS') then
    raise exception 'invalid_method' using errcode = 'P0001';
  end if;
  if p_paid is null or p_paid < 0 then
    raise exception 'invalid_paid' using errcode = 'P0001';
  end if;
  if p_dining_type not in ('TAKEAWAY', 'DINE_IN') then
    raise exception 'invalid_dining_type' using errcode = 'P0001';
  end if;

  -- Idempotensi: key sudah pernah dipakai -> kembalikan sale yang sama.
  select * into v_existing from public.sales
  where idempotency_key = p_idempotency_key;
  if found then
    return public.pos_sale_receipt(v_existing.id, v_existing.receipt_no)
      || jsonb_build_object('idempotent_replay', true);
  end if;

  v_q := public.pos_quote(p_items, p_discount_pct);
  v_total := (v_q ->> 'total')::integer;
  if p_paid < v_total then
    raise exception 'insufficient_payment' using errcode = 'P0001';
  end if;
  v_change := p_paid - v_total;

  v_receipt := 'MJ-' || to_char(now() at time zone 'Asia/Jakarta', 'YYMMDD')
    || '-' || lpad(nextval('public.sale_receipt_seq')::text, 4, '0');

  insert into public.sales (
    receipt_no, dining_type, table_id, subtotal, discount_amount,
    tax_amount, service_amount, total, idempotency_key, created_by
  ) values (
    v_receipt, p_dining_type,
    case when p_dining_type = 'DINE_IN' then p_table_id end,
    (v_q ->> 'subtotal')::integer,
    (v_q ->> 'discount_amount')::integer,
    (v_q ->> 'tax_amount')::integer,
    (v_q ->> 'service_amount')::integer,
    v_total, p_idempotency_key, auth.uid()
  ) returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := (v_item ->> 'product_id')::bigint;
    v_qty := (v_item ->> 'qty')::integer;
    select name, price into v_name, v_price
    from public.products where id = v_pid;
    select coalesce(jsonb_agg(jsonb_build_object(
             'modifier_id', m.id, 'name', m.name,
             'price_delta', m.price_delta) order by m.name), '[]'::jsonb)
      into v_mods
    from jsonb_array_elements(coalesce(v_item -> 'modifier_ids',
                                       '[]'::jsonb)) e
    join public.modifiers m on m.id = e.value::bigint;

    insert into public.sale_items (
      sale_id, product_id, product_name, unit_price, qty, note, modifiers
    ) values (
      v_sale_id, v_pid,
      v_name,
      v_price + coalesce((
        select sum(m.price_delta)
        from jsonb_array_elements(coalesce(v_item -> 'modifier_ids',
                                           '[]'::jsonb)) e
        join public.modifiers m on m.id = e.value::bigint
      ), 0),
      v_qty, nullif(trim(v_item ->> 'note'), ''), v_mods
    );
  end loop;

  insert into public.payments (sale_id, method, amount, paid, change_amount)
  values (v_sale_id, p_method, v_total, p_paid, v_change);

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('sale', v_sale_id::text, 'CHECKOUT',
          jsonb_build_object('total', v_total, 'method', p_method),
          auth.uid());

  return public.pos_sale_receipt(v_sale_id, v_receipt)
    || jsonb_build_object('change', v_change, 'idempotent_replay', false);
end;
$$;

-- Nomor struk berurutan.
create sequence if not exists public.sale_receipt_seq start 1;

-- ---------------------------------------------------------------------------
-- Struk: data sale + item snapshot + pembayaran.
-- ---------------------------------------------------------------------------
create or replace function public.pos_sale_receipt(
  p_sale_id bigint,
  p_receipt_no text default null
)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'sale_id', s.id,
    'receipt_no', s.receipt_no,
    'created_at', s.created_at,
    'status', s.status,
    'dining_type', s.dining_type,
    'subtotal', s.subtotal,
    'discount_amount', s.discount_amount,
    'tax_amount', s.tax_amount,
    'service_amount', s.service_amount,
    'total', s.total,
    'refund_amount', s.refund_amount,
    'payment', coalesce((
      select jsonb_build_object(
        'method', p.method, 'paid', p.paid,
        'change_amount', p.change_amount)
      from public.payments p where p.sale_id = s.id limit 1
    ), 'null'::jsonb),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_name', si.product_name,
        'unit_price', si.unit_price,
        'qty', si.qty,
        'note', si.note,
        'modifiers', si.modifiers
      ) order by si.id)
      from public.sale_items si where si.sale_id = s.id
    ), '[]'::jsonb),
    'refunds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'amount', r.amount, 'reason', r.reason,
        'created_at', r.created_at) order by r.id)
      from public.refunds r where r.sale_id = s.id
    ), '[]'::jsonb)
  )
  from public.sales s
  where s.id = p_sale_id
     or (p_receipt_no is not null and s.receipt_no = p_receipt_no);
$$;

-- ---------------------------------------------------------------------------
-- Refund (S02 gate): uang historis TIDAK dihapus; status + akumulasi dicatat.
-- ---------------------------------------------------------------------------
create or replace function public.pos_refund(
  p_sale_id bigint,
  p_amount integer,
  p_reason text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sale public.sales%rowtype;
  v_new_refund integer;
  v_status text;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_refund_amount' using errcode = 'P0001';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'invalid_refund_reason' using errcode = 'P0001';
  end if;

  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then
    raise exception 'sale_not_found' using errcode = 'P0001';
  end if;

  v_new_refund := v_sale.refund_amount + p_amount;
  if v_new_refund > v_sale.total then
    raise exception 'refund_exceeds_total' using errcode = 'P0001';
  end if;

  v_status := case when v_new_refund = v_sale.total
                   then 'REFUNDED' else 'PARTIALLY_REFUNDED' end;

  insert into public.refunds (sale_id, amount, reason, created_by)
  values (p_sale_id, p_amount, trim(p_reason), auth.uid());

  update public.sales
     set refund_amount = v_new_refund, status = v_status
   where id = p_sale_id;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('sale', p_sale_id::text, 'REFUND',
          jsonb_build_object('amount', p_amount, 'reason', trim(p_reason)),
          auth.uid());

  return public.pos_sale_receipt(p_sale_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Ringkasan dashboard (S02-09): hanya sale FINAL (net terhadap refund).
-- ---------------------------------------------------------------------------
create or replace function public.pos_dashboard_summary()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'today_revenue', coalesce(sum(total - refund_amount) filter (
      where created_at >= date_trunc('day',
        now() at time zone 'Asia/Jakarta')
      and status <> 'REFUNDED'), 0),
    'today_transactions', count(*) filter (
      where created_at >= date_trunc('day',
        now() at time zone 'Asia/Jakarta')
      and status <> 'REFUNDED'),
    'today_refunds', coalesce(sum(refund_amount) filter (
      where created_at >= date_trunc('day',
        now() at time zone 'Asia/Jakarta')), 0),
    'all_time_revenue', coalesce(sum(total - refund_amount)
      filter (where status <> 'REFUNDED'), 0),
    'all_time_transactions', count(*) filter (where status <> 'REFUNDED')
  )
  from public.sales;
$$;

-- Fungsi privat: hanya operator; anon tidak menyentuh uang.
do $$
declare
  f text;
begin
  foreach f in array array[
    'pos_line_total(bigint, integer, jsonb)',
    'pos_quote(jsonb, numeric)',
    'pos_checkout(jsonb, text, integer, text, bigint, numeric, text)',
    'pos_sale_receipt(bigint, text)',
    'pos_refund(bigint, integer, text)',
    'pos_dashboard_summary()'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format(
      'grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

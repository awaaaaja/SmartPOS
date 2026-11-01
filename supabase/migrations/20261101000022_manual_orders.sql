-- 0022_manual_orders.sql
-- Fitur Pesanan manual (tab Pesanan): operator membuat pesanan atas nama
-- pelanggan (nama + WA opsional + meja + item), dan menambah item pada
-- pesanan aktif ("minta lagi"). Tanpa menyentuh jalur QR pelanggan.
--
-- Invarian yang dijaga:
--   * Uang: harga item = snapshot server lewat pos_line_total (produk aktif,
--     qty 1..99, modifier sah) — sama seperti qr_submit_draft; klien tidak
--     pernah memercayai harga/hitungan.
--   * Subtotal DIHITUNG ULANG dari seluruh baris item di server, bukan
--     ditambah dari kiriman klien.
--   * Pesanan manual lahir CLAIMED (operator yang menulis = sudah diterima);
--     tidak kena lazy-expired (hanya PENDING) dan tidak memicu banner QR.
--   * Uang final TETAP dari pos_checkout; draft hanya status + bukti jejak.

-- ---------------------------------------------------------------------------
-- 1. Buat pesanan manual. Nama pelanggan WAJIB (pengenal pesanan manual);
--    meja wajib aktif; 1..30 item per pembuatan.
-- ---------------------------------------------------------------------------
create or replace function public.qr_manual_order_create(
  p_table_id bigint,
  p_customer_name text,
  p_customer_phone text default null,
  p_items jsonb default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_label text;
  v_draft_id bigint;
  v_subtotal integer := 0;
  v_count integer := 0;
  v_item jsonb;
  v_pid bigint;
  v_qty integer;
  v_name text;
  v_price integer;
  v_line integer;
  v_mods jsonb;
  v_cname text;
  v_cphone text;
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;

  v_cname := nullif(trim(coalesce(p_customer_name, '')), '');
  if v_cname is null or char_length(v_cname) > 60 then
    raise exception 'invalid_customer_name' using errcode = 'P0001',
      hint = 'Nama pesanan wajib diisi, maksimal 60 huruf.';
  end if;
  v_cphone := nullif(trim(coalesce(p_customer_phone, '')), '');
  if v_cphone is not null and char_length(v_cphone) > 24 then
    raise exception 'invalid_customer_phone' using errcode = 'P0001';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 30 then
    raise exception 'invalid_items' using errcode = 'P0001';
  end if;

  select label into v_label
  from public.dining_tables
  where id = p_table_id and is_enabled;
  if v_label is null then
    raise exception 'table_not_found' using errcode = 'P0001',
      hint = 'Meja tidak ada atau sedang dinonaktifkan.';
  end if;

  insert into public.qr_drafts (
    table_id, table_label, status, client_key,
    claimed_at, claimed_by, customer_name, customer_phone
  ) values (
    p_table_id, v_label, 'CLAIMED',
    'manual-' || encode(extensions.gen_random_bytes(12), 'hex'),
    now(), auth.uid(), v_cname, v_cphone
  )
  returning id into v_draft_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := (v_item ->> 'product_id')::bigint;
    v_qty := (v_item ->> 'qty')::integer;
    -- Validasi produk aktif + modifier + qty memakai helper pos (Sprint 02).
    v_line := public.pos_line_total(v_pid, v_qty, v_item -> 'modifier_ids');
    select name, price into v_name, v_price
    from public.products where id = v_pid;
    select coalesce(jsonb_agg(jsonb_build_object(
             'modifier_id', m.id, 'name', m.name,
             'price_delta', m.price_delta) order by m.name), '[]'::jsonb)
      into v_mods
    from jsonb_array_elements(coalesce(v_item -> 'modifier_ids',
                                       '[]'::jsonb)) e
    join public.modifiers m on m.id = e.value::bigint;

    insert into public.qr_draft_items (
      draft_id, product_id, product_name, unit_price, qty, modifiers, note
    ) values (
      v_draft_id, v_pid, v_name,
      v_line / v_qty,   -- harga per satuan hasil hitung server (integer aman)
      v_qty, v_mods, nullif(trim(v_item ->> 'note'), '')
    );
    v_subtotal := v_subtotal + v_line;
    v_count := v_count + 1;
  end loop;

  update public.qr_drafts
     set subtotal = v_subtotal, item_count = v_count
   where id = v_draft_id;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('qr_draft', v_draft_id::text, 'CREATE_MANUAL',
          jsonb_build_object('table_label', v_label,
                             'customer_name', v_cname,
                             'item_count', v_count,
                             'subtotal', v_subtotal),
          auth.uid());

  return public.qr_draft_json(v_draft_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Tambah item pesanan aktif ("minta lagi"). Hanya PENDING/CLAIMED/
--    PREPARING; draft selesai/dibatalkan/kedaluwarsa ditolak jujur.
--    Subtotal & item_count dihitung ulang dari seluruh baris item.
-- ---------------------------------------------------------------------------
create or replace function public.qr_draft_add_items(
  p_draft_id bigint,
  p_items jsonb default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
  v_subtotal integer;
  v_count integer;
  v_item jsonb;
  v_pid bigint;
  v_qty integer;
  v_name text;
  v_price integer;
  v_line integer;
  v_mods jsonb;
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 30 then
    raise exception 'invalid_items' using errcode = 'P0001';
  end if;

  select status into v_status
  from public.qr_drafts
  where id = p_draft_id
  for update;

  if v_status is null then
    raise exception 'draft_not_editable' using errcode = 'P0001',
      hint = 'Pesanan tidak ditemukan.';
  end if;
  if v_status not in ('PENDING', 'CLAIMED', 'PREPARING') then
    raise exception 'draft_not_editable' using errcode = 'P0001',
      hint = 'Hanya pesanan aktif (Baru masuk/Diterima/Diproses) yang bisa '
             'ditambah itemnya. Pesanan selesai/batal/kedaluwarsa tidak bisa.';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := (v_item ->> 'product_id')::bigint;
    v_qty := (v_item ->> 'qty')::integer;
    v_line := public.pos_line_total(v_pid, v_qty, v_item -> 'modifier_ids');
    select name, price into v_name, v_price
    from public.products where id = v_pid;
    select coalesce(jsonb_agg(jsonb_build_object(
             'modifier_id', m.id, 'name', m.name,
             'price_delta', m.price_delta) order by m.name), '[]'::jsonb)
      into v_mods
    from jsonb_array_elements(coalesce(v_item -> 'modifier_ids',
                                       '[]'::jsonb)) e
    join public.modifiers m on m.id = e.value::bigint;

    insert into public.qr_draft_items (
      draft_id, product_id, product_name, unit_price, qty, modifiers, note
    ) values (
      p_draft_id, v_pid, v_name,
      v_line / v_qty,
      v_qty, v_mods, nullif(trim(v_item ->> 'note'), '')
    );
  end loop;

  -- Hitung ulang dari seluruh baris item (jujur; bukan tambahan klien).
  select coalesce(sum(unit_price * qty), 0), count(*)
    into v_subtotal, v_count
  from public.qr_draft_items
  where draft_id = p_draft_id;

  update public.qr_drafts
     set subtotal = v_subtotal, item_count = v_count
   where id = p_draft_id;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('qr_draft', p_draft_id::text, 'ADD_ITEMS',
          jsonb_build_object('item_count', v_count, 'subtotal', v_subtotal),
          auth.uid());

  return public.qr_draft_json(p_draft_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Grants: operator (authenticated) saja; anon tidak punya akses.
-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'qr_manual_order_create(bigint, text, text, jsonb)',
    'qr_draft_add_items(bigint, jsonb)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format(
      'grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

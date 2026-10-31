-- 0018_qr_payment_pref.sql
-- Fase 1 rencana wizard web QR (docs/plan-qr-wizard-notif.md §A2).
-- Menambahkan preferensi pembayaran & identitas pelanggan OPSIONAL ke draft:
--   pay_intent      PAY_NOW | OPEN_BILL   (niat bayar dari langkah 1 wizard)
--   pay_method      CASH | QRIS | TRANSFER (hanya bermakna saat PAY_NOW)
--   customer_name   (opsional, <= 60 char) untuk penagihan di tab Pesanan
--   customer_phone  (opsional, <= 24 char) nomor WA untuk [Hubungi WA]
--
-- qr_submit_draft diperluas menjadi 6 param (4 baru DEFAULT NULL) sehingga
-- klien lama (3 argumen) & seluruh test integrasi lama tetap sah.
-- Harga TETAP snapshot server; preferensi/identitas hanya meta, tidak
-- mengubah perhitungan uang.

-- ---------------------------------------------------------------------------
-- Kolom baru pada qr_drafts (idempoten).
-- ---------------------------------------------------------------------------
alter table public.qr_drafts
  add column if not exists pay_intent text,
  add column if not exists pay_method text,
  add column if not exists customer_name text,
  add column if not exists customer_phone text;

-- CHECK via drop+add supaya aman diulang (Postgres tak punya ADD IF NOT EXISTS).
do $$
declare c text;
begin
  foreach c in array array[
    'qr_drafts_pay_intent_check',
    'qr_drafts_pay_method_check',
    'qr_drafts_customer_name_check',
    'qr_drafts_customer_phone_check'
  ] loop
    execute format('alter table public.qr_drafts drop constraint if exists %I', c);
  end loop;

  alter table public.qr_drafts
    add constraint qr_drafts_pay_intent_check
      check (pay_intent is null or pay_intent in ('PAY_NOW', 'OPEN_BILL')),
    add constraint qr_drafts_pay_method_check
      check (pay_method is null or pay_method in ('CASH', 'QRIS', 'TRANSFER')),
    add constraint qr_drafts_customer_name_check
      check (customer_name is null or char_length(customer_name) <= 60),
    add constraint qr_drafts_customer_phone_check
      check (customer_phone is null or char_length(customer_phone) <= 24);
end $$;

-- ---------------------------------------------------------------------------
-- qr_draft_json: sertakan preferensi bayar + identitas.
-- ---------------------------------------------------------------------------
create or replace function public.qr_draft_json(p_draft_id bigint)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'draft_id', d.id,
    'ref_code', 'Q' || lpad(d.id::text, 5, '0'),
    'table_id', d.table_id,
    'table_label', d.table_label,
    'status', d.status,
    'subtotal', d.subtotal,
    'item_count', d.item_count,
    'created_at', d.created_at,
    'expires_at', d.expires_at,
    'sale_id', d.sale_id,
    'pay_intent', d.pay_intent,
    'pay_method', d.pay_method,
    'customer_name', d.customer_name,
    'customer_phone', d.customer_phone,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_id', i.product_id,
        'product_name', i.product_name,
        'unit_price', i.unit_price,
        'qty', i.qty,
        'modifiers', i.modifiers,
        'note', i.note) order by i.id)
      from public.qr_draft_items i where i.draft_id = d.id
    ), '[]'::jsonb)
  )
  from public.qr_drafts d
  where d.id = p_draft_id;
$$;

-- ---------------------------------------------------------------------------
-- qr_submit_draft: 6 param (2 lama + 4 baru DEFAULT NULL). Klien lama tetap
-- sah. Validasi: method wajib null kecuali PAY_NOW; nama/phone di-TRIM dan
-- panjangnya dibatasi; string kosong -> null.
-- ---------------------------------------------------------------------------
drop function if exists public.qr_submit_draft(text, text, jsonb);

create function public.qr_submit_draft(
  p_table_token text,
  p_client_key text,
  p_items jsonb,
  p_pay_intent text default null,
  p_pay_method text default null,
  p_customer_name text default null,
  p_customer_phone text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_table_id bigint;
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
  v_recent integer;
  v_intent text := nullif(trim(coalesce(p_pay_intent, '')), '');
  v_method text := nullif(trim(coalesce(p_pay_method, '')), '');
  v_cname text := nullif(trim(coalesce(p_customer_name, '')), '');
  v_cphone text := nullif(trim(coalesce(p_customer_phone, '')), '');
begin
  if p_client_key is null or length(p_client_key) < 8 then
    raise exception 'missing_client_key' using errcode = 'P0001';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 30 then
    raise exception 'invalid_items' using errcode = 'P0001';
  end if;

  -- Validasi preferensi bayar (semantik, bukan cuma CHECK).
  if v_intent is not null and v_intent not in ('PAY_NOW', 'OPEN_BILL') then
    raise exception 'invalid_pay_intent' using errcode = 'P0001';
  end if;
  if v_method is not null and v_method not in ('CASH', 'QRIS', 'TRANSFER') then
    raise exception 'invalid_pay_method' using errcode = 'P0001';
  end if;
  if v_method is not null and v_intent is distinct from 'PAY_NOW' then
    raise exception 'pay_method_requires_pay_now'
      using errcode = 'P0001',
            hint = 'Metode pembayaran hanya berlaku untuk bayar sekarang.';
  end if;
  if v_cname is not null and char_length(v_cname) > 60 then
    raise exception 'invalid_customer_name' using errcode = 'P0001';
  end if;
  if v_cphone is not null and char_length(v_cphone) > 24 then
    raise exception 'invalid_customer_phone' using errcode = 'P0001';
  end if;

  select id, label into v_table_id, v_label
  from public.dining_tables
  where qr_token_hash = public.hash_table_token(p_table_token)
    and is_enabled;
  if v_table_id is null then
    raise exception 'invalid_table_token' using errcode = 'P0001';
  end if;

  -- Idempotensi: key sama pada meja yang sama = draft yang sama dikembalikan.
  select id into v_draft_id from public.qr_drafts
  where table_id = v_table_id and client_key = p_client_key;
  if found then
    return public.qr_draft_json(v_draft_id)
      || jsonb_build_object('idempotent_replay', true);
  end if;

  -- Rate limit sederhana: maksimal 5 draft per meja dalam 10 menit terakhir.
  select count(*) into v_recent from public.qr_drafts
  where table_id = v_table_id
    and created_at > now() - interval '10 minutes';
  if v_recent >= 5 then
    raise exception 'rate_limited'
      using errcode = 'P0001',
            hint = 'Terlalu sering mengirim pesanan; coba lagi beberapa menit lagi.';
  end if;

  insert into public.qr_drafts (
    table_id, table_label, client_key,
    pay_intent, pay_method, customer_name, customer_phone
  ) values (
    v_table_id, v_label, p_client_key,
    v_intent, v_method, v_cname, v_cphone
  )
  returning id into v_draft_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := (v_item ->> 'product_id')::bigint;
    v_qty := (v_item ->> 'qty')::integer;
    -- Validasi produk aktif + modifier + qty memakai helper pos Sprint 02.
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

  return public.qr_draft_json(v_draft_id)
    || jsonb_build_object('idempotent_replay', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants: anon hanya submit (signature baru); helper draft tetap operator.
-- ---------------------------------------------------------------------------
do $$
begin
  execute 'revoke all on function public.qr_submit_draft(text, text, jsonb,
             text, text, text, text) from public, authenticated';
  execute 'grant execute on function public.qr_submit_draft(text, text, jsonb,
             text, text, text, text) to anon';
end $$;

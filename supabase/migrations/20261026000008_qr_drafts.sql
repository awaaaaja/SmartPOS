-- 0008_qr_drafts.sql
-- Sprint 03 (S03-01…S03-09): pesanan QR pelanggan = DRAFT, bukan sale.
-- Pelanggan submit lewat SECURITY DEFINER (anon); operator melihat draft di
-- layar POS, mengambil (claim) ke keranjang, lalu membayar memakai
-- pos_checkout Sprint 02. Draft TIDAK pernah mengubah omzet/harga; semua
-- harga dihitung ulang server saat checkout.

-- ---------------------------------------------------------------------------
-- Tabel draft QR. RLS aktif tanpa policy = tertutup; hanya fungsi definer.
-- ---------------------------------------------------------------------------
create table if not exists public.qr_drafts (
  id bigint generated always as identity primary key,
  table_id bigint not null references public.dining_tables (id),
  table_label text not null,
  status text not null default 'PENDING'
    check (status in ('PENDING', 'CLAIMED', 'EXPIRED', 'CANCELLED', 'COMPLETED')),
  client_key text not null,           -- idempotensi: satu key = satu draft per meja
  subtotal integer not null default 0 check (subtotal >= 0),
  item_count integer not null default 0 check (item_count >= 0),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '2 hours',
  claimed_at timestamptz,
  claimed_by uuid references auth.users (id),
  sale_id bigint,                     -- diisi setelah operator membayar (bukti jejak)
  unique (table_id, client_key)
);

create table if not exists public.qr_draft_items (
  id bigint generated always as identity primary key,
  draft_id bigint not null references public.qr_drafts (id) on delete cascade,
  product_id bigint not null references public.products (id),
  product_name text not null,          -- snapshot saat submit
  unit_price integer not null check (unit_price >= 0),
  qty integer not null check (qty > 0),
  modifiers jsonb not null default '[]'::jsonb,
  note text
);

create index if not exists qr_drafts_status_idx
  on public.qr_drafts (status, created_at desc);
create index if not exists qr_draft_items_draft_idx
  on public.qr_draft_items (draft_id);

alter table public.qr_drafts enable row level security;
alter table public.qr_draft_items enable row level security;
-- Tanpa policy: anon & authenticated tidak bisa membaca/menulis langsung.

-- ---------------------------------------------------------------------------
-- Helper: bentuk JSON satu draft + item (dipakai submit, list, claim).
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
-- Submit draft (publik anon): validasi token, katalog, qty, rate limit,
-- idempotensi client_key. Harga = snapshot server, bukan kiriman klien.
-- ---------------------------------------------------------------------------
create or replace function public.qr_submit_draft(
  p_table_token text,
  p_client_key text,
  p_items jsonb
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
begin
  if p_client_key is null or length(p_client_key) < 8 then
    raise exception 'missing_client_key' using errcode = 'P0001';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 30 then
    raise exception 'invalid_items' using errcode = 'P0001';
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

  insert into public.qr_drafts (table_id, table_label, client_key)
  values (v_table_id, v_label, p_client_key)
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
-- Daftar draft (operator): hanya PENDING yang masih hidup; yang lewat
-- expires_at ditandai EXPIRED saat dibaca (lazy, tanpa cron).
-- ---------------------------------------------------------------------------
create or replace function public.qr_list_drafts()
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_rows jsonb;
begin
  update public.qr_drafts
     set status = 'EXPIRED'
   where status = 'PENDING' and expires_at < now();

  select coalesce(jsonb_agg(d ORDER BY d ->> 'created_at'), '[]'::jsonb)
    into v_rows
  from (
    select public.qr_draft_json(id) as d
    from public.qr_drafts
    where status = 'PENDING'
    order by created_at
  ) s;
  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- Claim atomik: hanya satu operator bisa mengambil draft PENDING.
-- ---------------------------------------------------------------------------
create or replace function public.qr_claim_draft(p_draft_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_updated bigint;
begin
  update public.qr_drafts
     set status = 'CLAIMED', claimed_at = now(), claimed_by = auth.uid()
   where id = p_draft_id
     and status = 'PENDING'
     and expires_at >= now()
  returning id into v_updated;

  if v_updated is null then
    raise exception 'draft_not_claimable'
      using errcode = 'P0001',
            hint = 'Draft sudah diambil, dibatalkan, atau kedaluwarsa.';
  end if;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('qr_draft', p_draft_id::text, 'CLAIM', '{}'::jsonb, auth.uid());

  return public.qr_draft_json(p_draft_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Batalkan draft (operator) + tandai selesai setelah checkout (jejak audit).
-- ---------------------------------------------------------------------------
create or replace function public.qr_cancel_draft(p_draft_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_updated bigint;
begin
  update public.qr_drafts
     set status = 'CANCELLED'
   where id = p_draft_id and status in ('PENDING', 'CLAIMED')
  returning id into v_updated;
  if v_updated is null then
    raise exception 'draft_not_cancelable' using errcode = 'P0001';
  end if;
  return public.qr_draft_json(p_draft_id);
end;
$$;

create or replace function public.qr_complete_draft(
  p_draft_id bigint,
  p_sale_id bigint
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  update public.qr_drafts
     set status = 'COMPLETED', sale_id = p_sale_id
   where id = p_draft_id and status = 'CLAIMED' and sale_id is null;
  if not found then
    raise exception 'draft_not_claimed' using errcode = 'P0001';
  end if;
  return public.qr_draft_json(p_draft_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants: anon hanya boleh submit draft; sisanya operator.
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'qr_draft_json(bigint)',
    'qr_list_drafts()',
    'qr_claim_draft(bigint)',
    'qr_cancel_draft(bigint)',
    'qr_complete_draft(bigint, bigint)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format(
      'grant execute on function public.%s to authenticated', f);
  end loop;

  execute 'revoke all on function public.qr_submit_draft(text, text, jsonb)
            from public, authenticated';
  execute 'grant execute on function public.qr_submit_draft(text, text, jsonb)
            to anon';
end $$;

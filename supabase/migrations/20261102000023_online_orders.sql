-- 0023_online_orders.sql
-- Pesanan Online lewat web (tanpa QR meja, tanpa login):
--   1. customer_address pada qr_drafts (opsional; WAJIB untuk COD).
--   2. pay_intent diperluas: AT_PLACE (ambil di kasir, bayar di tempat)
--      | COD (diantar ke alamat, tunai saat diterima). Nilai lama
--      (PAY_NOW | OPEN_BILL) tetap sah — wizard QR lama tidak berubah.
--   3. Meja virtual self-healing "Pesanan Online": qr_drafts.table_id NOT NULL
--      dan seluruh alur lama (kartu pesanan, banner, Diterima/Diproses/Bayar,
--      tambah item, klaim -> checkout) memakai tabel ini, jadi pesanan online
--      ikut alur utuh tanpa menyentuh kode lama. Self-healing: bila baris ini
--      dihapus operator, RPC berikutnya membuatnya lagi.
--   4. get_online_menu(): menu publik TANPA token (dipanggil web mode
--      ?mode=online). Tanpa mode & tanpa token tetap "QR tidak valid".
--   5. qr_online_submit(): submit anon — nama & WA wajib, alamat wajib saat
--      COD, 1..30 item, harga snapshot server (pos_line_total), rate limit,
--      lahir PENDING (banner operator aktif).
-- Uang: tidak ada perubahan — total final tetap dari pos_checkout.

-- ---------------------------------------------------------------------------
-- 1. Kolom alamat + perluasan CHECK (pola drop+add aman diulang, pola 0018).
-- ---------------------------------------------------------------------------
alter table public.qr_drafts
  add column if not exists customer_address text;

do $$
begin
  execute 'alter table public.qr_drafts
             drop constraint if exists qr_drafts_customer_address_check';
  alter table public.qr_drafts
    add constraint qr_drafts_customer_address_check
      check (customer_address is null or char_length(customer_address) <= 200);

  execute 'alter table public.qr_drafts
             drop constraint if exists qr_drafts_pay_intent_check';
  alter table public.qr_drafts
    add constraint qr_drafts_pay_intent_check
      check (pay_intent is null or pay_intent in
             ('PAY_NOW', 'OPEN_BILL', 'AT_PLACE', 'COD'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. qr_draft_json: sertakan alamat (kartu pesanan & balasan RPC memakai ini).
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
    'customer_address', d.customer_address,
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
-- 3. Meja virtual self-healing. Token sengaja dibuat dari string tetap yang
--    tidak pernah dibagikan — QR-nya memang tidak valid (jujur), karena
--    pesanan online datang lewat link web, bukan QR meja.
-- ---------------------------------------------------------------------------
create or replace function public.ensure_online_table()
returns bigint
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id bigint;
begin
  select id into v_id
  from public.dining_tables where label = 'Pesanan Online';

  if v_id is null then
    insert into public.dining_tables (label, qr_token_hash, is_enabled)
    values ('Pesanan Online',
            public.hash_table_token('__smartpos_online_orders__'),
            true)
    on conflict do nothing;
    select id into v_id
    from public.dining_tables where label = 'Pesanan Online';
  end if;

  return v_id;
end;
$$;

revoke all on function public.ensure_online_table()
  from public, authenticated, anon;

-- ---------------------------------------------------------------------------
-- 4. get_online_menu: seperti get_public_menu tapi tanpa token meja.
--    Hanya untuk mode online; tidak membocorkan data selain katalog aktif.
-- ---------------------------------------------------------------------------
create or replace function public.get_online_menu()
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id bigint;
  v_label text;
begin
  v_id := public.ensure_online_table();
  select label into v_label from public.dining_tables where id = v_id;

  return jsonb_build_object(
    'table', jsonb_build_object('id', v_id, 'label', v_label),
    'categories', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'name', c.name,
          'products', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', p.id,
                'name', p.name,
                'price', p.price,
                'photo_url', p.photo_url,
                'modifiers', coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'id', m.id,
                      'name', m.name,
                      'price_delta', m.price_delta,
                      'min_select', pm.min_select,
                      'max_select', pm.max_select
                    )
                    order by m.name
                  )
                  from product_modifiers pm
                  join modifiers m on m.id = pm.modifier_id
                  where pm.product_id = p.id and m.is_active
                ), '[]'::jsonb)
              )
              order by p.name
            )
            from products p
            where p.category_id = c.id
              and p.is_active
              and p.archived_at is null
          ), '[]'::jsonb)
        )
        order by c.sort_order, c.name
      )
      from product_categories c
      where c.archived_at is null
        and exists (
          select 1 from products p2
          where p2.category_id = c.id
            and p2.is_active and p2.archived_at is null
        )
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. qr_online_submit: submit pesanan online (anon, tanpa token meja).
--    Validasi: nama & WA wajib; alamat wajib hanya untuk COD; pay_intent
--    hanya AT_PLACE | COD; item 1..30; harga snapshot pos_line_total.
--    Idempoten per client_key (retry = draft yang sama, tanpa baris dobel).
--    Rate limit: maks 5 pesanan per nomor WA & maks 100 global per 10 menit.
--    Draft lahir PENDING dengan masa aktif 24 jam (operator harus sempat
--    membuka papan pesanan; lazy expiry tetap sama seperti QR meja).
-- ---------------------------------------------------------------------------
create or replace function public.qr_online_submit(
  p_client_key text,
  p_customer_name text,
  p_customer_phone text,
  p_customer_address text,
  p_pay_intent text,
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
  v_global integer;
  v_intent text := nullif(trim(coalesce(p_pay_intent, '')), '');
  v_cname text := nullif(trim(coalesce(p_customer_name, '')), '');
  v_cphone text := nullif(trim(coalesce(p_customer_phone, '')), '');
  v_address text := nullif(trim(coalesce(p_customer_address, '')), '');
begin
  if p_client_key is null or length(p_client_key) < 8 then
    raise exception 'missing_client_key' using errcode = 'P0001';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 30 then
    raise exception 'invalid_items' using errcode = 'P0001';
  end if;
  if v_cname is null or char_length(v_cname) > 60 then
    raise exception 'invalid_customer_name'
      using errcode = 'P0001',
            hint = 'Nama pemesan wajib diisi (maks 60 karakter).';
  end if;
  if v_cphone is null or char_length(v_cphone) > 24 then
    raise exception 'invalid_customer_phone'
      using errcode = 'P0001',
            hint = 'Nomor WhatsApp wajib diisi (maks 24 karakter).';
  end if;
  if v_intent not in ('AT_PLACE', 'COD') then
    raise exception 'invalid_pay_intent'
      using errcode = 'P0001',
            hint = 'Pilih Bayar di tempat (AT_PLACE) atau COD.';
  end if;
  if v_intent = 'COD' and v_address is null then
    raise exception 'invalid_customer_address'
      using errcode = 'P0001',
            hint = 'Alamat wajib diisi untuk pesanan COD (diantar).';
  end if;
  if v_address is not null and char_length(v_address) > 200 then
    raise exception 'invalid_customer_address'
      using errcode = 'P0001',
            hint = 'Alamat maks 200 karakter.';
  end if;

  v_table_id := public.ensure_online_table();
  select label into v_label
  from public.dining_tables where id = v_table_id;

  -- Idempotensi: key sama = draft yang sama dikembalikan (tanpa baris dobel).
  select id into v_draft_id from public.qr_drafts
  where table_id = v_table_id and client_key = p_client_key;
  if found then
    return public.qr_draft_json(v_draft_id)
      || jsonb_build_object('idempotent_replay', true);
  end if;

  -- Rate limit: per nomor WA (pelanggan biasa tidak lebih dari 5 dalam
  -- 10 menit) + pagu global sebagai jaring pengaman dari banjir kiriman.
  select count(*) into v_recent from public.qr_drafts
  where table_id = v_table_id
    and customer_phone = v_cphone
    and created_at > now() - interval '10 minutes';
  if v_recent >= 5 then
    raise exception 'rate_limited'
      using errcode = 'P0001',
            hint = 'Terlalu sering mengirim pesanan dari nomor ini; coba lagi beberapa menit lagi.';
  end if;

  select count(*) into v_global from public.qr_drafts
  where table_id = v_table_id
    and created_at > now() - interval '10 minutes';
  if v_global >= 100 then
    raise exception 'rate_limited'
      using errcode = 'P0001',
            hint = 'Pesanan online sedang ramah sekali; coba lagi beberapa menit lagi.';
  end if;

  insert into public.qr_drafts (
    table_id, table_label, client_key,
    pay_intent, customer_name, customer_phone, customer_address,
    expires_at
  ) values (
    v_table_id, v_label, p_client_key,
    v_intent, v_cname, v_cphone, v_address,
    now() + interval '24 hours'
  )
  returning id into v_draft_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pid := (v_item ->> 'product_id')::bigint;
    v_qty := (v_item ->> 'qty')::integer;
    -- Validasi produk aktif + modifier + qty memakai helper pos (snapshot
    -- harga server — kiriman harga palsu dari klien tidak pernah dipakai).
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
-- 6. Grants: anon hanya boleh MEMBACA menu online & MENGIRIM pesanan online.
--    Helper internal (ensure_online_table) tertutup — hanya dipanggil dari
--    SECURITY DEFINER milik owner.
-- ---------------------------------------------------------------------------
do $$
begin
  execute 'revoke all on function public.get_online_menu() from public';
  execute 'revoke all on function public.get_online_menu()
             from authenticated';
  execute 'grant execute on function public.get_online_menu() to anon';

  execute 'revoke all on function public.qr_online_submit(text, text, text,
             text, text, jsonb) from public, authenticated';
  execute 'grant execute on function public.qr_online_submit(text, text, text,
             text, text, jsonb) to anon';
end $$;

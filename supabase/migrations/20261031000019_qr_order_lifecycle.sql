-- 0019_qr_order_lifecycle.sql
-- Fase C rencana (docs/plan-qr-wizard-notif.md §C2): siklus hidup pesanan
-- untuk tab Pesanan — status PREPARING baru, papan aktif (bukan hanya
-- PENDING), complete boleh tanpa sale (Open Bill disajikan dulu), dan
-- pelunasan mengaitkan sale ke draft COMPLETED yang belum dibayar.
--
-- Uang TIDAK berubah: total final tetap dari keranjang saat pos_checkout;
-- draft hanya status + bukti jejak.

-- ---------------------------------------------------------------------------
-- 1. CHECK status: + PREPARING (drop + recreate; idempoten).
-- ---------------------------------------------------------------------------
do $$
begin
  execute 'alter table public.qr_drafts drop constraint if exists qr_drafts_status_check';
  alter table public.qr_drafts
    add constraint qr_drafts_status_check
    check (status in ('PENDING', 'CLAIMED', 'PREPARING',
                      'EXPIRED', 'CANCELLED', 'COMPLETED'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. qr_mark_preparing (baru): CLAIMED -> PREPARING, atomik + audit.
-- ---------------------------------------------------------------------------
create or replace function public.qr_mark_preparing_impl(p_draft_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_updated bigint;
begin
  update public.qr_drafts
     set status = 'PREPARING'
   where id = p_draft_id and status = 'CLAIMED'
  returning id into v_updated;

  if v_updated is null then
    raise exception 'draft_not_claimed' using errcode = 'P0001',
      hint = 'Hanya pesanan berstatus Diterima (CLAIMED) yang bisa diproses.';
  end if;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('qr_draft', p_draft_id::text, 'PREPARE', '{}'::jsonb, auth.uid());

  return public.qr_draft_json(p_draft_id);
end;
$$;

create or replace function public.qr_mark_preparing(p_draft_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.qr_mark_preparing_impl(p_draft_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. qr_complete_draft: semantik baru (drop + recreate, kini DEFAULT null).
--    - CLAIMED/PREPARING -> COMPLETED, sale_id = p_sale_id (boleh null)
--    - COMPLETED + sale null + p_sale_id terisi -> kaitkan pelunasan
--    - COMPLETED + sale sama -> idempoten
--    - selain itu -> draft_not_completable
-- ---------------------------------------------------------------------------
drop function if exists public.qr_complete_draft(bigint, bigint);
drop function if exists public.qr_complete_draft_impl(bigint, bigint);

create function public.qr_complete_draft_impl(
  p_draft_id bigint,
  p_sale_id bigint default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
  v_sale bigint;
begin
  select status, sale_id into v_status, v_sale
  from public.qr_drafts
  where id = p_draft_id
  for update;

  if not found then
    raise exception 'draft_not_completable' using errcode = 'P0001',
      hint = 'Draft tidak ada.';
  end if;

  if v_status in ('CLAIMED', 'PREPARING') then
    update public.qr_drafts
       set status = 'COMPLETED', sale_id = p_sale_id
     where id = p_draft_id;
  elsif v_status = 'COMPLETED' and v_sale is null
        and p_sale_id is not null then
    -- Pelunasan Open Bill: kaitkan sale ke draft yang sudah selesai.
    update public.qr_drafts
       set sale_id = p_sale_id
     where id = p_draft_id;
  elsif v_status = 'COMPLETED' and v_sale is not distinct from p_sale_id then
    -- Idempoten: status + sale sudah sesuai permintaan.
    null;
  else
    raise exception 'draft_not_completable' using errcode = 'P0001',
      hint = 'Hanya pesanan Diterima/Diproses yang bisa diselesaikan.';
  end if;

  return public.qr_draft_json(p_draft_id);
end;
$$;

create function public.qr_complete_draft(
  p_draft_id bigint,
  p_sale_id bigint default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.qr_complete_draft_impl(p_draft_id, p_sale_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. qr_cancel_draft: boleh juga dari PREPARING.
-- ---------------------------------------------------------------------------
create or replace function public.qr_cancel_draft_impl(p_draft_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_updated bigint;
begin
  update public.qr_drafts
     set status = 'CANCELLED'
   where id = p_draft_id
     and status in ('PENDING', 'CLAIMED', 'PREPARING')
  returning id into v_updated;
  if v_updated is null then
    raise exception 'draft_not_cancelable' using errcode = 'P0001';
  end if;
  return public.qr_draft_json(p_draft_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. qr_list_drafts: PAPAN AKTIF — PENDING, CLAIMED, PREPARING, dan
--    COMPLETED yang belum dibayar (sale_id null). Lazy EXPIRED tetap
--    hanya untuk PENDING yang lewat expires_at.
-- ---------------------------------------------------------------------------
create or replace function public.qr_list_drafts_impl()
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
    where status in ('PENDING', 'CLAIMED', 'PREPARING')
       or (status = 'COMPLETED' and sale_id is null)
    order by created_at
  ) s;
  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Grants: wrapper operator baru/diubah; impl hanya untuk wrapper
--    (dijalankan sebagai definer). Klien anon tidak memegang apa pun di
--    jalur ini (sudah lewat qr_submit_draft sendiri).
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'qr_mark_preparing(bigint)',
    'qr_complete_draft(bigint, bigint)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format(
      'grant execute on function public.%s to authenticated', f);
  end loop;

  foreach f in array array[
    'qr_mark_preparing_impl(bigint)',
    'qr_complete_draft_impl(bigint, bigint)'
  ]
  loop
    execute format(
      'revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

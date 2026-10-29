-- 0015_operator_guard.sql
-- Audit keamanan: guard is_operator() SERAGAM untuk semua RPC yang boleh
-- dipanggil langsung oleh klien (authenticated). Sebelumnya hanya RPC dari
-- Sprint 06 (0013/0014) yang memeriksa; RPC Sprint 02-05 hanya mengandalkan
-- grant + asumsi satu akun. Fungsi SECURITY DEFINER melewati RLS, sehingga
-- akun authenticated NON-operator mana pun bisa memanggil RPC lama via
-- PostgREST. Pola wrapper sama dengan 0013/0014: nama lama di-rename ke
-- *_impl (grant dicabut), wrapper bertanda tangan memeriksa lalu mendelegasikan.
--
-- Helper internal yang tidak boleh disentuh klien langsung (hanya dipanggil
-- dari dalam fungsi SECURITY DEFINER lain, termasuk jalur anon
-- qr_submit_draft) dicabut grant-nya, TANPA guard, agar jalur anon tetap hidup:
--   pos_line_total, qr_draft_json, hash_table_token.

-- ---------------------------------------------------------------------------
-- 1. Helper internal: cabut grant (owner tetap bisa memanggil dari definer).
-- ---------------------------------------------------------------------------
revoke all on function public.pos_line_total(bigint, integer, jsonb)
  from public, anon, authenticated;
revoke all on function public.qr_draft_json(bigint)
  from public, anon, authenticated;
revoke all on function public.hash_table_token(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Simpan badan lama sebagai *_impl (tanpa perubahan isi), tutup grant.
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'pos_quote(jsonb, numeric)',
    'pos_checkout(jsonb, text, integer, text, bigint, numeric, text)',
    'pos_sale_receipt(bigint, text)',
    'pos_dashboard_summary()',
    'qr_list_drafts()',
    'qr_claim_draft(bigint)',
    'qr_cancel_draft(bigint)',
    'qr_complete_draft(bigint, bigint)',
    'qr_create_table(text)',
    'qr_rotate_token(bigint)',
    'inv_save_ingredient(bigint, text, text, numeric, integer)',
    'inv_receive_purchase(bigint)',
    'inv_save_recipe(bigint, numeric, jsonb)',
    'inv_hpp(bigint)',
    'cost_allocate(bigint, text, integer)',
    'cash_shift_status()',
    'cash_shift_open(integer)',
    'cash_shift_close(integer, text)',
    'pos_reports(date, date)'
  ]
  loop
    execute format('alter function public.%s rename to %s_impl',
                   f, split_part(f, '(', 1));
    execute format('revoke all on function public.%s_impl%s from public, anon, authenticated',
                   split_part(f, '(', 1), substr(f, length(split_part(f, '(', 1)) + 1));
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Wrapper bertanda tangan: periksa operator, lalu delegasikan ke *_impl.
--    Volatility dijaga sama dengan badan asli agar perilaku cache/plan tidak
--    berubah. Parameter dan default disalin persis dari badan asli.
-- ---------------------------------------------------------------------------

-- pos_quote: klien mengirim keranjang mentah; total tetap dihitung server.
create or replace function public.pos_quote(
  p_items jsonb,
  p_discount_pct numeric default 0
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.pos_quote_impl(p_items, p_discount_pct);
end;
$$;

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
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.pos_checkout_impl(p_items, p_method, p_paid, p_dining_type,
                                  p_table_id, p_discount_pct, p_idempotency_key);
end;
$$;

create or replace function public.pos_sale_receipt(
  p_sale_id bigint,
  p_receipt_no text default null
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.pos_sale_receipt_impl(p_sale_id, p_receipt_no);
end;
$$;

create or replace function public.pos_dashboard_summary()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.pos_dashboard_summary_impl();
end;
$$;

create or replace function public.qr_list_drafts()
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.qr_list_drafts_impl();
end;
$$;

create or replace function public.qr_claim_draft(p_draft_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.qr_claim_draft_impl(p_draft_id);
end;
$$;

create or replace function public.qr_cancel_draft(p_draft_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.qr_cancel_draft_impl(p_draft_id);
end;
$$;

create or replace function public.qr_complete_draft(
  p_draft_id bigint,
  p_sale_id bigint
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

create or replace function public.qr_create_table(p_label text)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.qr_create_table_impl(p_label);
end;
$$;

create or replace function public.qr_rotate_token(p_table_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.qr_rotate_token_impl(p_table_id);
end;
$$;

create or replace function public.inv_save_ingredient(
  p_id bigint default null,
  p_name text default null,
  p_base_unit text default null,
  p_reorder_level numeric default 0,
  p_unit_cost integer default 0
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.inv_save_ingredient_impl(p_id, p_name, p_base_unit,
                                         p_reorder_level, p_unit_cost);
end;
$$;

create or replace function public.inv_receive_purchase(p_purchase_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.inv_receive_purchase_impl(p_purchase_id);
end;
$$;

create or replace function public.inv_save_recipe(
  p_product_id bigint,
  p_yield_qty numeric default 1,
  p_items jsonb default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.inv_save_recipe_impl(p_product_id, p_yield_qty, p_items);
end;
$$;

create or replace function public.inv_hpp(p_product_id bigint)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.inv_hpp_impl(p_product_id);
end;
$$;

create or replace function public.cost_allocate(
  p_expense_id bigint default null,
  p_target_ref text default null,
  p_amount integer default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.cost_allocate_impl(p_expense_id, p_target_ref, p_amount);
end;
$$;

create or replace function public.cash_shift_status()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.cash_shift_status_impl();
end;
$$;

create or replace function public.cash_shift_open(
  p_opening_cash integer default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.cash_shift_open_impl(p_opening_cash);
end;
$$;

create or replace function public.cash_shift_close(
  p_actual_cash integer default null,
  p_note text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.cash_shift_close_impl(p_actual_cash, p_note);
end;
$$;

create or replace function public.pos_reports(
  p_from date default null,
  p_to date default null
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;
  return public.pos_reports_impl(p_from, p_to);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Grants: wrapper hanya untuk authenticated; publik/anon tertutup.
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'pos_quote(jsonb, numeric)',
    'pos_checkout(jsonb, text, integer, text, bigint, numeric, text)',
    'pos_sale_receipt(bigint, text)',
    'pos_dashboard_summary()',
    'qr_list_drafts()',
    'qr_claim_draft(bigint)',
    'qr_cancel_draft(bigint)',
    'qr_complete_draft(bigint, bigint)',
    'qr_create_table(text)',
    'qr_rotate_token(bigint)',
    'inv_save_ingredient(bigint, text, text, numeric, integer)',
    'inv_receive_purchase(bigint)',
    'inv_save_recipe(bigint, numeric, jsonb)',
    'inv_hpp(bigint)',
    'cost_allocate(bigint, text, integer)',
    'cash_shift_status()',
    'cash_shift_open(integer)',
    'cash_shift_close(integer, text)',
    'pos_reports(date, date)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format(
      'grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';

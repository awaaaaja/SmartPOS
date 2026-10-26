-- 0009_table_qr_api.sql
-- Sprint 03 (S03-01): buat/rotasi token meja di server.
-- Plaintext token hanya DIKEMBALIKAN SEKALI (waktu dibuat/dirotasi);
-- yang tersimpan tetap hash SHA-256 (D-03). Operator via REST RLS.

create or replace function public.qr_create_table(p_label text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_label text := trim(coalesce(p_label, ''));
  v_id bigint;
  v_token text;
begin
  if length(v_label) < 1 or length(v_label) > 40 then
    raise exception 'invalid_label' using errcode = 'P0001';
  end if;

  v_token := encode(extensions.gen_random_bytes(16), 'hex');
  insert into public.dining_tables (label, qr_token_hash)
  values (v_label, public.hash_table_token(v_token))
  returning id into v_id;

  return jsonb_build_object(
    'table_id', v_id, 'label', v_label, 'token', v_token);
end;
$$;

create or replace function public.qr_rotate_token(p_table_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_token text;
  v_label text;
begin
  v_token := encode(extensions.gen_random_bytes(16), 'hex');
  update public.dining_tables
     set qr_token_hash = public.hash_table_token(v_token),
         token_version = token_version + 1
   where id = p_table_id
  returning label into v_label;
  if v_label is null then
    raise exception 'table_not_found' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'table_id', p_table_id, 'label', v_label, 'token', v_token);
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'qr_create_table(text)', 'qr_rotate_token(bigint)'
  ]
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format(
      'grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

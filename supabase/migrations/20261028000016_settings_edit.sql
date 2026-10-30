-- 0016_settings_edit.sql
-- K06-08: Pengaturan usaha (nama, alamat, zona waktu, pajak, biaya layanan)
-- bisa diedit dari aplikasi. Sebelumnya halaman Pengaturan read-only; perubahan
-- hanya lewat SQL konsol. Pola mengikuti RPC guarded 0015: guard is_operator()
-- dengan errcode 42501, validasi di server (klien tidak dipercaya), tulis
-- business_settings id = 1, catat audit_events, lalu kembalikan baris terbaru.

create or replace function public.settings_save(
  p_name text,
  p_address text default null,
  p_timezone text default 'Asia/Jakarta',
  p_tax_rate numeric default 0,
  p_service_rate numeric default 0
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_name text := trim(coalesce(p_name, ''));
  v_address text := nullif(trim(coalesce(p_address, '')), '');
  v_timezone text := trim(coalesce(p_timezone, ''));
  v_tax numeric := coalesce(p_tax_rate, 0);
  v_service numeric := coalesce(p_service_rate, 0);
  v_before jsonb;
  v_row public.business_settings%rowtype;
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;

  -- Validasi di server: klien bisa mengirim apa pun lewat PostgREST.
  if length(v_name) < 2 or length(v_name) > 80 then
    raise exception 'invalid_name' using errcode = 'P0001';
  end if;
  if v_address is not null and length(v_address) > 200 then
    raise exception 'invalid_address' using errcode = 'P0001';
  end if;
  if length(v_timezone) > 64
     or not exists (select 1 from pg_timezone_names where name = v_timezone) then
    raise exception 'invalid_timezone' using errcode = 'P0001';
  end if;
  -- Tarif disimpan sebagai fraksi (0.10 = 10%), batas kolom hanya >= 0.
  if v_tax is null or v_tax < 0 or v_tax > 1 then
    raise exception 'invalid_tax_rate' using errcode = 'P0001';
  end if;
  if v_service is null or v_service < 0 or v_service > 1 then
    raise exception 'invalid_service_rate' using errcode = 'P0001';
  end if;

  select to_jsonb(b) into v_before
    from public.business_settings b where b.id = 1;
  if v_before is null then
    raise exception 'settings_not_found' using errcode = 'P0001';
  end if;

  update public.business_settings
     set name = v_name,
         address = v_address,
         timezone = v_timezone,
         tax_rate = v_tax,
         service_rate = v_service,
         updated_at = now()
   where id = 1
  returning * into v_row;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('business_settings', '1', 'UPDATE',
          jsonb_build_object(
            'before', v_before - 'updated_at' - 'created_at',
            'after', jsonb_build_object(
              'name', v_name, 'address', v_address, 'timezone', v_timezone,
              'tax_rate', v_tax, 'service_rate', v_service)),
          auth.uid());

  return to_jsonb(v_row);
end;
$$;

-- Klien hanya boleh lewat PostgREST sebagai authenticated; guard di dalam
-- badan fungsi yang memutuskan anon/non-operator.
revoke all on function public.settings_save(text, text, text, numeric, numeric)
  from public, anon;
grant execute on function public.settings_save(text, text, text, numeric, numeric)
  to authenticated;

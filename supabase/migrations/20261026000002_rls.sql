-- 0002_rls.sql
-- Sprint 01 (S01-06): RLS ketat. Operator tunggal mengelola semua data privat;
-- anon/publik TIDAK punya policy apa pun sehingga tertutup rapat.
-- Jalur publik hanya lewat SECURITY DEFINER di 0003_public_menu_api.sql.

-- Penanda operator: email pada business_settings cocok dengan email sesi.
create or replace function public.is_operator() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.business_settings b
    where lower(b.operator_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function public.is_operator() from public;
grant execute on function public.is_operator() to authenticated;

-- ---------------------------------------------------------------------------
-- Terapkan RLS pada seluruh tabel privat.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'business_settings', 'product_categories', 'products',
    'product_price_history', 'modifiers', 'product_modifiers', 'dining_tables'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists operator_all on public.%I', t);
    execute format(
      'create policy operator_all on public.%I for all to authenticated '
      'using (public.is_operator()) with check (public.is_operator())',
      t
    );
  end loop;
end $$;

-- Tabel sensitif: operator hanya bisa membaca (konfigurasi diubah via migrasi).
-- business_settings tetap terbaca agar aplikasi bisa memverifikasi identitas.

-- Stub lingkungan CI untuk menguji migrasi di PostgreSQL polos.
-- TIDAK untuk produksi Supabase (di sana skema auth sudah asli).
create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text
);

create or replace function auth.uid() returns uuid
language sql stable as $$ select null::uuid $$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$ select null::jsonb $$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;

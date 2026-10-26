-- 0004_fix_pgcrypto_search_path.sql
-- Temuan REVIEW: di Supabase, pgcrypto terpasang di skema `extensions`,
-- sehingga `digest(...)` tak terlihat dari fungsi dengan search_path=public.
-- Migrasi ini membuat hash token memakai kualifikasi eksplisit dan berlaku
-- juga di PostgreSQL polos CI (skema extensions dibuat dahulu).

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create or replace function public.hash_table_token(p_token text)
returns text
language sql immutable as $$
  select encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

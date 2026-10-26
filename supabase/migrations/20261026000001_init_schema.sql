-- 0001_init_schema.sql
-- Sprint 01 (S01-05): skema dasar satu usaha, satu operator.
-- Seluruh uang memakai integer Rupiah. Tidak ada tabel tenant/branch/staff/kitchen.

-- pgcrypto dipasang di skema `extensions` agar sama dengan proyek Supabase
-- asli; fungsi hash selalu memakai kualifikasi `extensions.digest`.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Satu record konfigurasi usaha sekaligus penanda akun operator tunggal.
-- ---------------------------------------------------------------------------
create table if not exists public.business_settings (
  id bigint primary key check (id = 1),
  name text not null,
  address text,
  timezone text not null default 'Asia/Jakarta',
  operator_email text not null,
  tax_rate numeric(6, 4) not null default 0 check (tax_rate >= 0),
  service_rate numeric(6, 4) not null default 0 check (service_rate >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Katalog
-- ---------------------------------------------------------------------------
create table if not exists public.product_categories (
  id bigint generated always as identity primary key,
  name text not null unique,
  sort_order integer not null default 0,
  archived_at timestamptz
);

create table if not exists public.products (
  id bigint generated always as identity primary key,
  category_id bigint references public.product_categories (id),
  name text not null,
  price integer not null check (price >= 0),
  photo_url text,
  is_active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Harga lama tidak pernah hilang: setiap perubahan harga tercatat.
create table if not exists public.product_price_history (
  id bigint generated always as identity primary key,
  product_id bigint not null references public.products (id),
  old_price integer not null check (old_price >= 0),
  new_price integer not null check (new_price >= 0),
  reason text,
  changed_by uuid references auth.users (id),
  effective_at timestamptz not null default now()
);

create or replace function public.log_price_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.price is distinct from old.price then
    insert into public.product_price_history
      (product_id, old_price, new_price, changed_by)
    values (old.id, old.price, new.price, auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_products_price_history on public.products;
create trigger trg_products_price_history
  before update on public.products
  for each row execute function public.log_price_change();

-- Varian / topping dengan batas pilihan.
create table if not exists public.modifiers (
  id bigint generated always as identity primary key,
  name text not null,
  price_delta integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.product_modifiers (
  product_id bigint not null references public.products (id) on delete cascade,
  modifier_id bigint not null references public.modifiers (id) on delete cascade,
  min_select integer not null default 0,
  max_select integer not null default 1,
  primary key (product_id, modifier_id),
  check (min_select >= 0),
  check (max_select >= min_select)
);

-- ---------------------------------------------------------------------------
-- Meja dan QR: hanya hash token yang disimpan, token dapat dirotasi.
-- ---------------------------------------------------------------------------
create table if not exists public.dining_tables (
  id bigint generated always as identity primary key,
  label text not null unique,
  qr_token_hash text not null unique,
  token_version integer not null default 1,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- updated_at otomatis
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_business_settings_updated on public.business_settings;
create trigger trg_business_settings_updated
  before update on public.business_settings
  for each row execute function public.set_updated_at();

drop trigger if exists trg_products_updated on public.products;
create trigger trg_products_updated
  before update on public.products
  for each row execute function public.set_updated_at();

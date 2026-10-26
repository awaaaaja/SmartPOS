-- 0005_sales.sql
-- Sprint 02 (S02-07): tabel transaksi final. Uang integer Rupiah.
-- Tidak ada tabel pesanan/dapur; sales hanya lahir dari POS (dan QR via POS).

create table if not exists public.sales (
  id bigint generated always as identity primary key,
  receipt_no text not null unique,
  status text not null default 'FINAL'
    check (status in ('FINAL', 'PARTIALLY_REFUNDED', 'REFUNDED')),
  dining_type text not null default 'TAKEAWAY'
    check (dining_type in ('TAKEAWAY', 'DINE_IN')),
  table_id bigint references public.dining_tables (id),
  subtotal integer not null check (subtotal >= 0),
  discount_amount integer not null default 0 check (discount_amount >= 0),
  tax_amount integer not null default 0 check (tax_amount >= 0),
  service_amount integer not null default 0 check (service_amount >= 0),
  total integer not null check (total >= 0),
  refund_amount integer not null default 0 check (refund_amount >= 0),
  idempotency_key text not null unique,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create table if not exists public.sale_items (
  id bigint generated always as identity primary key,
  sale_id bigint not null references public.sales (id) on delete cascade,
  product_id bigint references public.products (id),
  -- Snapshot: nama dan harga saat transaksi; edit menu lama tidak mengubah struk.
  product_name text not null,
  unit_price integer not null check (unit_price >= 0),
  qty integer not null check (qty > 0),
  note text,
  modifiers jsonb not null default '[]'::jsonb
    -- [{modifier_id, name, price_delta}] snapshot
);

create table if not exists public.payments (
  id bigint generated always as identity primary key,
  sale_id bigint not null references public.sales (id) on delete cascade,
  method text not null check (method in ('CASH', 'TRANSFER', 'QRIS')),
  amount integer not null check (amount >= 0),
  paid integer not null check (paid >= 0),
  change_amount integer not null default 0 check (change_amount >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.refunds (
  id bigint generated always as identity primary key,
  sale_id bigint not null references public.sales (id),
  amount integer not null check (amount > 0),
  reason text not null,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create table if not exists public.audit_events (
  id bigint generated always as identity primary key,
  entity text not null,
  entity_id text not null,
  action text not null,
  detail jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

-- RLS: operator tunggal; anon tanpa policy (tertutup).
do $$
declare
  t text;
begin
  foreach t in array array[
    'sales', 'sale_items', 'payments', 'refunds', 'audit_events'
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

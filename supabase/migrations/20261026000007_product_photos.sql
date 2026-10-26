-- 0007_product_photos.sql
-- Sprint 02 (S02-01): bucket foto produk di Supabase Storage.
-- Pembacaan publik (foto menu memang tampil di QR pelanggan); penulisan
-- hanya operator. Dilewati aman di Postgres polos (CI) tanpa skema storage.

do $$
begin
  if not exists (
    select 1 from information_schema.schemata where schema_name = 'storage'
  ) then
    raise notice 'skema storage tidak ada (CI/Postgres polos) - dilewati';
    return;
  end if;

  insert into storage.buckets (id, name, public)
  values ('product-photos', 'product-photos', true)
  on conflict (id) do nothing;

  drop policy if exists "product photos public read" on storage.objects;
  create policy "product photos public read" on storage.objects
    for select using (bucket_id = 'product-photos');

  drop policy if exists "product photos operator write" on storage.objects;
  create policy "product photos operator write" on storage.objects
    for all to authenticated
    using (public.is_operator() and bucket_id = 'product-photos')
    with check (public.is_operator() and bucket_id = 'product-photos');
end $$;

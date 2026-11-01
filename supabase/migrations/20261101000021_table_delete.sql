-- 0021_table_delete.sql
-- Fitur hapus meja (Meja & QR): qr_delete_table — guard operator, blokir
-- bila masih ada pesanan AKTIF, draft terminal ikut terhapus (tiket pesanan,
-- bukan buku uang), riwayat penjualan TIDAK dihapus — hanya tautan meja
-- dilepas (sales.table_id -> null). Uang integer tidak disentuh.

create or replace function public.qr_delete_table(p_table_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_label text;
  v_active integer;
  v_drafts integer;
  v_sales integer;
begin
  if not public.is_operator() then
    raise exception 'operator_required' using errcode = '42501';
  end if;

  select label into v_label
  from public.dining_tables where id = p_table_id;
  if v_label is null then
    raise exception 'table_not_found' using errcode = 'P0001';
  end if;

  -- Pesanan aktif = papan tab Pesanan: PENDING, CLAIMED, PREPARING, dan
  -- COMPLETED yang belum dibayar (sale_id null). Semuanya harus selesai
  -- dulu — menghapus meja dengan pesanan hidup akan membuang antrean.
  select count(*) into v_active
  from public.qr_drafts
  where table_id = p_table_id
    and (status in ('PENDING', 'CLAIMED', 'PREPARING')
         or (status = 'COMPLETED' and sale_id is null));
  if v_active > 0 then
    raise exception 'table_has_active_orders'
      using errcode = 'P0001',
            hint = 'Selesaikan atau batalkan pesanan aktif di meja ini dulu.';
  end if;

  -- Sisa draft pasti terminal (EXPIRED/CANCELLED/COMPLETED berbayar):
  -- tiket pesanan ikut terhapus; item-nya cascade. Buku uang tetap di sales.
  delete from public.qr_drafts where table_id = p_table_id;
  get diagnostics v_drafts = row_count;

  -- Riwayat penjualan DIPERTAHANKAN: hanya tautan meja dilepas agar baris
  -- uang tetap utuh (receipt, item, pembayaran, refund tidak berubah).
  update public.sales set table_id = null where table_id = p_table_id;
  get diagnostics v_sales = row_count;

  delete from public.dining_tables where id = p_table_id;

  insert into public.audit_events (entity, entity_id, action, detail, created_by)
  values ('dining_table', p_table_id::text, 'DELETE',
          jsonb_build_object('label', v_label,
                             'drafts_removed', v_drafts,
                             'sales_detached', v_sales),
          auth.uid());

  return jsonb_build_object(
    'table_id', p_table_id, 'label', v_label,
    'drafts_removed', v_drafts, 'sales_detached', v_sales);
end;
$$;

do $$
begin
  execute 'revoke all on function public.qr_delete_table(bigint) from public, anon';
  execute 'grant execute on function public.qr_delete_table(bigint) to authenticated';
end $$;

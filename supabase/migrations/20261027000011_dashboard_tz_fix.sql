-- 0011_dashboard_tz_fix.sql
-- Perbaikan jujur (D-04: WIB = UTC+7 manual):
-- pos_dashboard_summary membandingkan created_at (timestamptz) dengan
-- date_trunc('day', now() at time zone 'Asia/Jakarta') yang bernilai naive
-- dan ditafsirkan Postgres sebagai UTC -> batas "hari ini" bergeser 7 jam
-- (omzet hari baru belum masuk sebelum pukul 07:00 WIB, dan rentang
-- sebelumnya ikut meleset). Kembalikan hasilnya ke timestamptz tengah malam
-- WIB yang benar via `at time zone 'Asia/Jakarta'`.

create or replace function public.pos_dashboard_summary()
returns jsonb
language sql stable security definer set search_path = public as $$
  with bounds as (
    select (date_trunc('day', now() at time zone 'Asia/Jakarta')
            at time zone 'Asia/Jakarta') as day_start
  )
  select jsonb_build_object(
    'today_revenue', coalesce(sum(total - refund_amount) filter (
      where created_at >= b.day_start and status <> 'REFUNDED'), 0),
    'today_transactions', count(*) filter (
      where created_at >= b.day_start and status <> 'REFUNDED'),
    'today_refunds', coalesce(sum(refund_amount) filter (
      where created_at >= b.day_start), 0),
    'all_time_revenue', coalesce(sum(total - refund_amount)
      filter (where status <> 'REFUNDED'), 0),
    'all_time_transactions', count(*) filter (where status <> 'REFUNDED')
  )
  from public.sales, bounds b;
$$;

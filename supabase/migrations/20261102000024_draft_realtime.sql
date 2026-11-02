-- 0024_draft_realtime.sql
-- Perbaikan notifikasi pesanan (laporan pengguna: notifikasi kadang delay,
-- papan pesanan harus di-refresh manual).
--
-- Penyebab: satu-satunya sumber pemberitahuan adalah polling 10 detik di
-- klien — pesanan baru baru terlihat pada siklus berikutnya, dan isolate
-- Flutter berhenti di background sehingga app yang dibuka dari recent apps
-- terasa "harus refresh". Perbaikan 3 lapis:
--   1. Migrasi ini: qr_drafts masuk publication `supabase_realtime`
--      (INSERT/UPDATE didorong realtime ke klien) + policy SELECT operator
--      — realtime memeriksa RLS dengan peran pelanggan, tanpa policy ini
--      event tidak pernah sampai.
--   2. Klien Flutter: langganan realtime + refresh saat app resume;
--      polling 10 detik dipertahankan sebagai FALLBACK (websocket gagal).
--   3. Anon TIDAK ikut: policy hanya `to authenticated`, sehingga uji anon
--      (test_online_orders T-07 & test_qr_drafts) tetap tertutup rapat.
--
-- Idempoten; aman di Postgres CI polos (stub membuat publication bila belum
-- ada — guard di bawah tetap menangani lingkungan tanpa publication).

-- 0) Hak baca tabel: RLS policy hanya berlaku bila ada GRANT. Supabase
--    hosted memberi grant ini bawaan (default privileges); Postgres CI polos
--    tidak — jadi dinyatakan eksplisit di sini (idempoten, anon tak disentuh).
grant select on public.qr_drafts to authenticated;

-- 1) Operator (dan hanya operator) boleh MEMBACA qr_drafts langsung.
--    Menulis tetap HANYA lewat RPC SECURITY DEFINER: tidak ada policy tulis
--    di sini, sehingga seluruh jalur lama (submit/claim/checkout) tak berubah.
drop policy if exists operator_read on public.qr_drafts;
create policy operator_read on public.qr_drafts
  for select to authenticated
  using (public.is_operator());

-- 2) Broadcast perubahan qr_drafts (guard: publication bisa tidak ada).
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'qr_drafts'
  ) then
    alter publication supabase_realtime add table public.qr_drafts;
  end if;
end $$;

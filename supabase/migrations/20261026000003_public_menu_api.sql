-- 0003_public_menu_api.sql
-- Sprint 01 (S01-06): jalur publik terproteksi.
-- Pelanggan QR hanya bisa membaca menu aktif lewat fungsi ini; tidak ada
-- akses langsung ke tabel privat (tanpa policy untuk anon).

create or replace function public.hash_table_token(p_token text)
returns text
language sql immutable as $$
  select encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

-- Menu publik untuk satu meja. Token salah/kedaluwarsa = error tegas.
create or replace function public.get_public_menu(p_table_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_table_id bigint;
  v_label text;
begin
  select id, label into v_table_id, v_label
  from public.dining_tables
  where qr_token_hash = public.hash_table_token(p_table_token)
    and is_enabled;

  if v_table_id is null then
    raise exception 'invalid_table_token'
      using errcode = 'P0001',
            hint = 'Token meja tidak dikenal atau sudah dirotasi.';
  end if;

  return jsonb_build_object(
    'table', jsonb_build_object('id', v_table_id, 'label', v_label),
    'categories', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'name', c.name,
          'products', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', p.id,
                'name', p.name,
                'price', p.price,
                'photo_url', p.photo_url,
                'modifiers', coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'id', m.id,
                      'name', m.name,
                      'price_delta', m.price_delta,
                      'min_select', pm.min_select,
                      'max_select', pm.max_select
                    )
                    order by m.name
                  )
                  from product_modifiers pm
                  join modifiers m on m.id = pm.modifier_id
                  where pm.product_id = p.id and m.is_active
                ), '[]'::jsonb)
              )
              order by p.name
            )
            from products p
            where p.category_id = c.id
              and p.is_active
              and p.archived_at is null
          ), '[]'::jsonb)
        )
        order by c.sort_order, c.name
      )
      from product_categories c
      where c.archived_at is null
        and exists (
          select 1 from products p2
          where p2.category_id = c.id and p2.is_active and p2.archived_at is null
        )
    ), '[]'::jsonb)
  );
end;
$$;

-- Fungsi publik hanya boleh dipanggil tanpa sesi (pelanggan QR).
revoke all on function public.get_public_menu(text) from public;
revoke all on function public.get_public_menu(text) from authenticated;
grant execute on function public.get_public_menu(text) to anon;

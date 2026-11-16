-- WARUNG DARUL ILMI v1.2
-- Perbaikan pembatasan jalur kasir di tingkat database.
-- Jalankan SATU KALI setelah migrasi v1-v4.

begin;

-- Pastikan setiap kasir memiliki jalur yang valid.
alter table public.profiles
  add column if not exists cashier_gender text;

-- Fungsi scope menggunakan pembandingan yang tahan terhadap spasi/huruf besar-kecil.
create or replace function public.can_access_order_gender(p_gender text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    public.is_super_admin()
    or exists (
      select 1
      from public.profiles p
      where p.id = (select auth.uid())
        and p.role::text = 'cashier'
        and lower(trim(coalesce(p.cashier_gender, ''))) = lower(trim(coalesce(p_gender, '')))
        and lower(trim(coalesce(p.cashier_gender, ''))) in ('putra', 'putri')
    ),
    false
  );
$$;

revoke all on function public.can_access_order_gender(text) from public, anon;
grant execute on function public.can_access_order_gender(text) to authenticated;

-- Hapus semua policy lama pada tabel orders agar tidak ada policy permisif
-- yang tanpa sengaja memberi kasir akses lintas jalur (policy PostgreSQL bersifat OR).
do $$
declare pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'orders'
  loop
    execute format('drop policy if exists %I on public.orders', pol.policyname);
  end loop;
end;
$$;

alter table public.orders enable row level security;

-- Pelanggan terdaftar hanya melihat miliknya; staf hanya melihat jalur yang diizinkan.
create policy wdi_orders_select_scoped
on public.orders
for select to authenticated
using (
  customer_id = (select auth.uid())
  or (select public.can_access_order_gender(guest_gender))
);

-- Kasir hanya dapat mengubah pesanan pada jalurnya; Super Admin dapat keduanya.
create policy wdi_orders_update_scoped
on public.orders
for update to authenticated
using ((select public.can_access_order_gender(guest_gender)))
with check ((select public.can_access_order_gender(guest_gender)));

-- Hapus semua policy item lama untuk mencegah akses silang melalui relasi item.
do $$
declare pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'order_items'
  loop
    execute format('drop policy if exists %I on public.order_items', pol.policyname);
  end loop;
end;
$$;

alter table public.order_items enable row level security;

create policy wdi_order_items_select_scoped
on public.order_items
for select to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_items.order_id
      and (
        o.customer_id = (select auth.uid())
        or (select public.can_access_order_gender(o.guest_gender))
      )
  )
);

-- Item pesanan dikelola oleh kasir sesuai jalurnya atau Super Admin.
create policy wdi_order_items_insert_scoped
on public.order_items
for insert to authenticated
with check (
  exists (
    select 1
    from public.orders o
    where o.id = order_items.order_id
      and (select public.can_access_order_gender(o.guest_gender))
  )
);

create policy wdi_order_items_update_scoped
on public.order_items
for update to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and (select public.can_access_order_gender(o.guest_gender))
  )
)
with check (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and (select public.can_access_order_gender(o.guest_gender))
  )
);

create policy wdi_order_items_delete_scoped
on public.order_items
for delete to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and (select public.can_access_order_gender(o.guest_gender))
  )
);

commit;

notify pgrst, 'reload schema';

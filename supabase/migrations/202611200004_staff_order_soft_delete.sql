-- Warung Darul Ilmi: soft delete pesanan, pemulihan 3 hari, pembersihan otomatis.
-- Jalankan sekali pada project Supabase yang sedang digunakan aplikasi.

create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

begin;

alter table public.orders
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null;

create index if not exists orders_deleted_at_idx
  on public.orders (deleted_at)
  where deleted_at is not null;

create or replace function public.soft_delete_staff_order(p_order_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gender text;
  v_deleted_at timestamptz;
begin
  if (select auth.uid()) is null or not coalesce(public.is_staff(), false) then
    raise exception 'Login petugas diperlukan untuk menghapus pesanan.';
  end if;

  select o.guest_gender, o.deleted_at
    into v_gender, v_deleted_at
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;
  if not public.can_access_order_gender(v_gender) then
    raise exception 'Akun petugas tidak memiliki akses ke jalur pesanan ini.';
  end if;
  if v_deleted_at is not null then
    raise exception 'Pesanan sudah berada di Sampah.';
  end if;

  update public.orders
  set deleted_at = clock_timestamp(),
      deleted_by = (select auth.uid()),
      updated_at = clock_timestamp()
  where id = p_order_id
  returning deleted_at into v_deleted_at;

  return v_deleted_at;
end;
$$;

create or replace function public.restore_staff_order(p_order_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gender text;
  v_deleted_at timestamptz;
begin
  if (select auth.uid()) is null or not coalesce(public.is_staff(), false) then
    raise exception 'Login petugas diperlukan untuk memulihkan pesanan.';
  end if;

  select o.guest_gender, o.deleted_at
    into v_gender, v_deleted_at
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;
  if not public.can_access_order_gender(v_gender) then
    raise exception 'Akun petugas tidak memiliki akses ke jalur pesanan ini.';
  end if;
  if v_deleted_at is null then
    raise exception 'Pesanan tidak sedang berada di Sampah.';
  end if;
  if v_deleted_at <= clock_timestamp() - interval '3 days' then
    raise exception 'Batas pemulihan 3 hari sudah lewat. Pesanan akan dihapus permanen.';
  end if;

  update public.orders
  set deleted_at = null,
      deleted_by = null,
      updated_at = clock_timestamp()
  where id = p_order_id;

  return v_deleted_at;
end;
$$;

create or replace function public.purge_expired_staff_orders()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted_count bigint;
begin
  delete from public.orders
  where deleted_at is not null
    and deleted_at <= clock_timestamp() - interval '3 days';

  get diagnostics v_deleted_count = row_count;
  return v_deleted_count;
end;
$$;

revoke all on function public.soft_delete_staff_order(uuid) from public, anon;
revoke all on function public.restore_staff_order(uuid) from public, anon;
grant execute on function public.soft_delete_staff_order(uuid) to authenticated;
grant execute on function public.restore_staff_order(uuid) to authenticated;

revoke all on function public.purge_expired_staff_orders() from public, anon, authenticated;
grant execute on function public.purge_expired_staff_orders() to postgres;

-- Browser hanya boleh mengubah status secara langsung. Kolom soft delete diubah via RPC.
revoke update on public.orders from authenticated;
grant update (status) on public.orders to authenticated;

-- Job bernama sama akan memperbarui jadwal yang sudah ada.
select cron.schedule(
  'wdi-purge-expired-orders',
  '* * * * *',
  'select public.purge_expired_staff_orders();'
);

notify pgrst, 'reload schema';
commit;

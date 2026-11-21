-- Warung Darul Ilmi: saat pesanan dibatalkan, arsipkan ke Sampah dalam satu transaksi.
-- Jalankan sekali setelah migration 202611200004_staff_order_soft_delete.sql.

create or replace function public.cancel_staff_order(p_order_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gender text;
  v_status text;
  v_deleted_at timestamptz;
begin
  if (select auth.uid()) is null or not coalesce(public.is_staff(), false) then
    raise exception 'Login petugas diperlukan untuk membatalkan pesanan.';
  end if;

  select o.guest_gender, o.status, o.deleted_at
    into v_gender, v_status, v_deleted_at
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

  if v_status = 'cancelled' then
    raise exception 'Pesanan sudah dibatalkan.';
  end if;

  if v_status = 'delivered' then
    raise exception 'Pesanan yang sudah diserahkan tidak dapat dibatalkan.';
  end if;

  update public.orders
  set status = 'cancelled',
      deleted_at = clock_timestamp(),
      deleted_by = (select auth.uid()),
      updated_at = clock_timestamp()
  where id = p_order_id
  returning deleted_at into v_deleted_at;

  return v_deleted_at;
end;
$$;

revoke all on function public.cancel_staff_order(uuid) from public, anon;
grant execute on function public.cancel_staff_order(uuid) to authenticated;

notify pgrst, 'reload schema';

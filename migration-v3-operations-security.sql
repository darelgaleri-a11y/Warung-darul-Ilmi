-- WARUNG DARUL ILMI v0.6: ruang kasir, rekening, dan jadwal operasional
-- Jalankan SATU KALI setelah migration-v2-guest-checkout.sql berhasil.
begin;

-- Identitas jalur kerja untuk setiap akun kasir.
alter table public.profiles
  add column if not exists cashier_gender text
  check (cashier_gender in ('Putra','Putri') or cashier_gender is null);

-- Kasir tanpa cashier_gender tidak memperoleh akses antrean sampai Super Admin menetapkan jalurnya.

-- Data rekening ditampilkan kepada pelanggan sebagai instruksi transfer.
alter table public.store_settings
  add column if not exists bank_name text,
  add column if not exists bank_account_number text,
  add column if not exists bank_account_name text,
  add column if not exists payment_instructions text;

-- Mencegah kasir mengubah role atau jalur kasir miliknya sendiri.
create or replace function public.protect_profile_role()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (new.role is distinct from old.role or new.cashier_gender is distinct from old.cashier_gender)
     and (select auth.uid()) is not null
     and not coalesce(public.is_super_admin(), false) then
    raise exception 'Hanya super admin yang boleh mengubah role dan jalur kasir.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Fungsi scope digunakan oleh RLS agar batas Putra/Putri berlaku di server.
create or replace function public.can_access_order_gender(p_gender text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(
    public.is_super_admin()
    or exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'cashier'::public.app_role
        and p.cashier_gender = p_gender
    ), false
  );
$$;

-- Ganti policy staff umum dengan policy terbatasi.
drop policy if exists "orders_select_owner_or_staff" on public.orders;
drop policy if exists "orders_staff_update" on public.orders;
create policy "orders_select_owner_or_scoped_staff"
on public.orders for select to authenticated
using (
  customer_id = (select auth.uid())
  or (select public.can_access_order_gender(guest_gender))
);
create policy "orders_update_scoped_staff"
on public.orders for update to authenticated
using ((select public.can_access_order_gender(guest_gender)))
with check ((select public.can_access_order_gender(guest_gender)));

-- Kasir hanya boleh melihat/mengelola item pesanan yang boleh diakses.
drop policy if exists "order_items_select_owner_or_staff" on public.order_items;
drop policy if exists "order_items_staff_manage" on public.order_items;
create policy "order_items_select_owner_or_scoped_staff"
on public.order_items for select to authenticated
using (exists (
  select 1 from public.orders o where o.id = order_items.order_id
  and (o.customer_id = (select auth.uid()) or (select public.can_access_order_gender(o.guest_gender)))
));
create policy "order_items_scoped_staff_manage"
on public.order_items for all to authenticated
using (exists (
  select 1 from public.orders o where o.id = order_items.order_id
  and (select public.can_access_order_gender(o.guest_gender))
))
with check (exists (
  select 1 from public.orders o where o.id = order_items.order_id
  and (select public.can_access_order_gender(o.guest_gender))
));

-- Batasi riwayat dan catatan pembayaran pada jalur gender yang sama.
drop policy if exists "payments_select_owner_or_staff" on public.payment_records;
drop policy if exists "payments_staff_update" on public.payment_records;
create policy "payments_select_owner_or_scoped_staff"
on public.payment_records for select to authenticated
using (exists (
  select 1 from public.orders o where o.id = payment_records.order_id
  and (o.customer_id = (select auth.uid()) or (select public.can_access_order_gender(o.guest_gender)))
));
create policy "payments_update_scoped_staff"
on public.payment_records for update to authenticated
using (exists (
  select 1 from public.orders o where o.id = payment_records.order_id
  and (select public.can_access_order_gender(o.guest_gender))
))
with check (exists (
  select 1 from public.orders o where o.id = payment_records.order_id
  and (select public.can_access_order_gender(o.guest_gender))
));

drop policy if exists "order_history_select_owner_or_staff" on public.order_status_history;
create policy "order_history_select_owner_or_scoped_staff"
on public.order_status_history for select to authenticated
using (exists (
  select 1 from public.orders o where o.id = order_status_history.order_id
  and (o.customer_id = (select auth.uid()) or (select public.can_access_order_gender(o.guest_gender)))
));

-- Hanya super admin boleh mengelola referensi dan pengaturan pusat.
-- Policy store_settings_admin_update yang sudah ada tetap berlaku.

commit;

-- WARUNG DARUL ILMI - Perbaikan riwayat status pesanan
-- Jalankan SATU KALI di Supabase SQL Editor.
-- Aman untuk data yang sudah ada; tidak menghapus pesanan atau riwayat.

begin;

-- 1. Riwayat status harus dicatat SETELAH baris orders tersimpan,
--    karena order_status_history.order_id memiliki foreign key ke orders.id.
create or replace function public.log_order_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_status_history
      (order_id, old_status, new_status, changed_by)
    values
      (new.id, null, new.status, (select auth.uid()));
  elsif new.status is distinct from old.status then
    insert into public.order_status_history
      (order_id, old_status, new_status, changed_by)
    values
      (new.id, old.status, new.status, (select auth.uid()));
  end if;

  return new;
end;
$$;

-- Hapus trigger lama yang berjalan BEFORE INSERT/UPDATE.
drop trigger if exists log_order_status_after_change on public.orders;

-- Trigger baru berjalan AFTER, sehingga foreign key sudah menemukan order induk.
create trigger log_order_status_after_change
  after insert or update of status on public.orders
  for each row execute procedure public.log_order_status_change();

-- 2. Pertahankan fungsi updated_at pada perubahan order.
create or replace function public.touch_order_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists touch_order_updated_at_before_update on public.orders;
create trigger touch_order_updated_at_before_update
  before update on public.orders
  for each row execute procedure public.touch_order_updated_at();

commit;

-- Pemeriksaan: trigger riwayat harus bertipe AFTER (tgtype mengandung bit 64).
select
  tgname,
  pg_get_triggerdef(oid) as trigger_definition
from pg_trigger
where tgrelid = 'public.orders'::regclass
  and not tgisinternal
  and tgname in ('log_order_status_after_change', 'touch_order_updated_at_before_update');

-- Warung Darul Ilmi: safe staff order editing.
-- Kasir hanya dapat mengedit jalur gender yang ditetapkan; Super Admin dapat keduanya.
-- Perubahan item dan total berlangsung dalam satu transaksi PostgreSQL.

begin;

create or replace function public.update_staff_order(
  p_order_id uuid,
  p_guest_name text,
  p_guest_gender text,
  p_guest_dormitory text,
  p_guest_class text,
  p_guest_phone text,
  p_customer_note text,
  p_delivery_date date,
  p_items jsonb
)
returns table (
  order_id uuid,
  total_amount bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_item jsonb;
  v_product_id bigint;
  v_quantity integer;
  v_price bigint;
  v_requested_total bigint := 0;
  v_total bigint;
begin
  if (select auth.uid()) is null then
    raise exception 'Login petugas diperlukan untuk mengubah pesanan.';
  end if;

  select o.id, o.guest_gender, o.payment_state, o.total_amount
    into v_order
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'Pesanan tidak ditemukan.';
  end if;

  if not public.can_access_order_gender(v_order.guest_gender) then
    raise exception 'Akun petugas tidak memiliki akses ke jalur pesanan ini.';
  end if;

  if p_guest_gender not in ('Putra', 'Putri')
     or not public.can_access_order_gender(p_guest_gender) then
    raise exception 'Akun petugas tidak boleh memindahkan pesanan ke jalur gender lain.';
  end if;

  if length(trim(coalesce(p_guest_name, ''))) < 2 then
    raise exception 'Nama santri minimal 2 karakter.';
  end if;
  if length(trim(coalesce(p_guest_dormitory, ''))) < 1
     or length(trim(coalesce(p_guest_class, ''))) < 1 then
    raise exception 'Asrama dan kelas wajib diisi.';
  end if;
  if p_delivery_date is null then
    raise exception 'Tanggal pengiriman wajib diisi.';
  end if;
  if coalesce(jsonb_typeof(p_items), '') <> 'array'
     or jsonb_array_length(p_items) < 1
     or jsonb_array_length(p_items) > 30 then
    raise exception 'Pesanan harus memiliki 1 sampai 30 jenis menu.';
  end if;

  -- Validasi seluruh produk dan hitung total sebelum menyentuh rincian lama.
  for v_item in
    select value from jsonb_array_elements(p_items)
  loop
    begin
      v_product_id := (v_item ->> 'product_id')::bigint;
      v_quantity := (v_item ->> 'quantity')::integer;
    exception when others then
      raise exception 'Data menu pesanan tidak valid.';
    end;

    if v_product_id is null or v_quantity is null or v_quantity < 1 or v_quantity > 50 then
      raise exception 'Produk atau jumlah menu tidak valid.';
    end if;

    select p.price into v_price
    from public.products p
    where p.id = v_product_id and p.is_available = true;

    if not found then
      raise exception 'Salah satu menu sudah tidak tersedia. Ganti dengan menu aktif.';
    end if;

    v_requested_total := v_requested_total + (v_price * v_quantity);
  end loop;

  -- Jangan membuat catatan pembayaran lunas menjadi berbeda dari total pesanan.
  if v_order.payment_state::text in ('paid', 'pending_verification')
     and v_requested_total <> v_order.total_amount then
    raise exception 'Pesanan memiliki pembayaran menunggu verifikasi atau sudah lunas. Perubahan menu/jumlah tidak boleh mengubah total tagihan.';
  end if;

  update public.orders
  set guest_name = trim(p_guest_name),
      guest_gender = p_guest_gender,
      guest_dormitory = trim(p_guest_dormitory),
      guest_class = trim(p_guest_class),
      guest_phone = nullif(trim(coalesce(p_guest_phone, '')), ''),
      customer_note = nullif(trim(coalesce(p_customer_note, '')), ''),
      delivery_date = p_delivery_date,
      updated_at = now()
  where id = p_order_id;

  delete from public.order_items oi where oi.order_id = p_order_id;

  for v_item in
    select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item ->> 'product_id')::bigint;
    v_quantity := (v_item ->> 'quantity')::integer;

    insert into public.order_items (
      order_id, product_id, product_name_snapshot, unit_price_snapshot, quantity
    )
    select p_order_id, p.id, p.name, p.price, v_quantity
    from public.products p
    where p.id = v_product_id and p.is_available = true;

    if not found then
      raise exception 'Menu berubah atau tidak tersedia saat penyimpanan. Silakan muat ulang lalu coba lagi.';
    end if;
  end loop;

  select o.total_amount into v_total
  from public.orders o
  where o.id = p_order_id;

  return query select p_order_id, v_total;
end;
$$;

revoke all on function public.update_staff_order(uuid, text, text, text, text, text, text, date, jsonb)
  from public, anon;
grant execute on function public.update_staff_order(uuid, text, text, text, text, text, text, date, jsonb)
  to authenticated;

notify pgrst, 'reload schema';

commit;

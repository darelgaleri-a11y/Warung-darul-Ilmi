-- WARUNG DARUL ILMI — Migration v2: Guest checkout
-- Jalankan SATU KALI setelah database-v1 berhasil dibuat.
-- Tidak menghapus tabel atau data yang sudah ada.

begin;

-- Guest orders tidak memiliki akun auth.
alter table public.orders
  alter column customer_id drop not null,
  add column if not exists guest_name text,
  add column if not exists guest_gender text
    check (guest_gender in ('Putra', 'Putri') or guest_gender is null),
  add column if not exists guest_dormitory text,
  add column if not exists guest_class text,
  add column if not exists guest_phone text;

-- Pesanan baru melalui RPC tamu harus menyimpan identitas tamu.
alter table public.orders
  add constraint orders_customer_or_guest_check
  check (
    (customer_id is not null and guest_name is null)
    or
    (customer_id is null and guest_name is not null
      and guest_gender is not null
      and guest_dormitory is not null
      and guest_class is not null)
  );

-- Hapus akses insert langsung untuk anon/authenticated. Semua checkout tamu
-- harus melewati RPC yang memvalidasi produk dan menghitung harga di server.
revoke insert on public.orders from anon, authenticated;
revoke insert on public.order_items from anon, authenticated;

-- Seed katalog contoh untuk uji integrasi. Ganti data ini melalui admin nanti.
insert into public.categories (name, sort_order, is_active)
values ('Makanan', 1, true), ('Minuman', 2, true), ('Camilan', 3, true)
on conflict (name) do nothing;

insert into public.products (id, category_id, name, description, sku, price, is_available)
values
  (1, (select id from public.categories where name='Makanan'), 'Nasi Ayam', 'Menu contoh', 'WDI-001', 12000, true),
  (2, (select id from public.categories where name='Makanan'), 'Nasi Goreng', 'Menu contoh', 'WDI-002', 10000, true),
  (3, (select id from public.categories where name='Makanan'), 'Mie Goreng', 'Menu contoh', 'WDI-003', 9000, true),
  (4, (select id from public.categories where name='Minuman'), 'Es Teh', 'Menu contoh', 'WDI-004', 4000, true),
  (5, (select id from public.categories where name='Minuman'), 'Air Mineral', 'Menu contoh', 'WDI-005', 3000, true),
  (6, (select id from public.categories where name='Camilan'), 'Roti Cokelat', 'Menu contoh', 'WDI-006', 5000, true)
on conflict (id) do update set
  category_id = excluded.category_id,
  name = excluded.name,
  description = excluded.description,
  price = excluded.price,
  is_available = excluded.is_available;

select setval(
  pg_get_serial_sequence('public.products', 'id'),
  greatest((select coalesce(max(id), 1) from public.products), 1),
  true
);

-- Fungsi checkout tamu:
-- - tidak membutuhkan login
-- - tanggal pengiriman dihitung server (hari ini tidak pernah dipilih)
-- - harga dan nama produk diambil dari tabel products
-- - pesanan dan item dibuat dalam satu transaksi
create or replace function public.create_guest_order(
  p_guest_name text,
  p_guest_gender text,
  p_guest_dormitory text,
  p_guest_class text,
  p_guest_phone text,
  p_customer_note text,
  p_items jsonb
)
returns table (
  order_id uuid,
  order_number text,
  delivery_date date,
  total_amount bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_order_number text;
  v_delivery_date date;
  v_total bigint;
  v_item jsonb;
  v_product_id bigint;
  v_quantity integer;
  v_count integer := 0;
begin
  if length(trim(coalesce(p_guest_name, ''))) < 2 then
    raise exception 'Nama santri wajib diisi.';
  end if;

  if p_guest_gender not in ('Putra', 'Putri') then
    raise exception 'Kategori santri tidak valid.';
  end if;

  if length(trim(coalesce(p_guest_dormitory, ''))) < 1
     or length(trim(coalesce(p_guest_class, ''))) < 1 then
    raise exception 'Asrama dan kelas wajib diisi.';
  end if;

  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1
     or jsonb_array_length(p_items) > 30 then
    raise exception 'Keranjang kosong atau jumlah item melebihi batas.';
  end if;

  insert into public.orders (
    customer_id, guest_name, guest_gender, guest_dormitory, guest_class,
    guest_phone, customer_note, delivery_date
  )
  values (
    null, trim(p_guest_name), p_guest_gender, trim(p_guest_dormitory),
    trim(p_guest_class), nullif(trim(coalesce(p_guest_phone, '')), ''),
    nullif(trim(coalesce(p_customer_note, '')), ''),
    public.next_delivery_date()
  )
  returning id, order_number, delivery_date
  into v_order_id, v_order_number, v_delivery_date;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item ->> 'product_id')::bigint;
    v_quantity := (v_item ->> 'quantity')::integer;

    if v_quantity is null or v_quantity < 1 or v_quantity > 50 then
      raise exception 'Jumlah produk tidak valid.';
    end if;

    insert into public.order_items (
      order_id, product_id, product_name_snapshot, unit_price_snapshot, quantity
    )
    select
      v_order_id, p.id, p.name, p.price, v_quantity
    from public.products p
    where p.id = v_product_id and p.is_available = true;

    if not found then
      raise exception 'Produk ID % tidak ditemukan atau tidak tersedia.', v_product_id;
    end if;

    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    raise exception 'Tidak ada item pesanan yang valid.';
  end if;

  select o.total_amount into v_total
  from public.orders o
  where o.id = v_order_id;

  return query select v_order_id, v_order_number, v_delivery_date, v_total;
end;
$$;

revoke all on function public.create_guest_order(text,text,text,text,text,text,jsonb) from public;
grant execute on function public.create_guest_order(text,text,text,text,text,text,jsonb) to anon, authenticated;

-- Staff tetap dapat membaca pesanan lewat policy yang sudah dibuat.
-- Guest tidak diberi hak select langsung; nomor pesanan dan tanggal dikembalikan
-- hanya sebagai hasil RPC untuk ditampilkan/diteruskan ke WhatsApp.

commit;

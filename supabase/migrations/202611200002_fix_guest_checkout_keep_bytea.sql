-- Warung Darul Ilmi: fix guest checkout RPC without changing the hash column type.
-- Keep public.orders.guest_access_token_hash as BYTEA.
-- Do NOT ALTER the column: payment_records RLS policy payments_insert_guest_token
-- depends on it. Existing order hashes remain untouched.

begin;

create or replace function public.create_guest_order(
  p_guest_name text,
  p_guest_gender text,
  p_guest_dormitory text,
  p_guest_class text,
  p_guest_phone text,
  p_customer_note text,
  p_items jsonb,
  p_access_token text
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
  v_token_hash bytea;
begin
  if length(trim(coalesce(p_guest_name, ''))) < 2 then
    raise exception 'Nama santri wajib diisi.';
  end if;

  if p_guest_gender is null or p_guest_gender not in ('Putra', 'Putri') then
    raise exception 'Kategori santri tidak valid.';
  end if;

  if length(trim(coalesce(p_guest_dormitory, ''))) < 1
     or length(trim(coalesce(p_guest_class, ''))) < 1 then
    raise exception 'Asrama dan kelas wajib diisi.';
  end if;

  if p_access_token is null
     or p_access_token !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'Token akses pesanan tidak valid.';
  end if;

  if coalesce(jsonb_typeof(p_items), '') <> 'array' then
    raise exception 'Keranjang kosong atau format item tidak valid.';
  end if;

  if jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 30 then
    raise exception 'Keranjang kosong atau jumlah item melebihi batas.';
  end if;

  -- digest() returns BYTEA, matching the existing column type.
  v_token_hash := extensions.digest(
    convert_to(lower(p_access_token), 'UTF8'),
    'sha256'
  );

  insert into public.orders (
    customer_id, guest_name, guest_gender, guest_dormitory, guest_class,
    guest_phone, customer_note, delivery_date, guest_access_token_hash
  )
  values (
    null, trim(p_guest_name), p_guest_gender, trim(p_guest_dormitory),
    trim(p_guest_class), nullif(trim(coalesce(p_guest_phone, '')), ''),
    nullif(trim(coalesce(p_customer_note, '')), ''),
    public.next_delivery_date(), v_token_hash
  )
  returning id, orders.order_number, orders.delivery_date
  into v_order_id, v_order_number, v_delivery_date;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    begin
      v_product_id := (v_item ->> 'product_id')::bigint;
      v_quantity := (v_item ->> 'quantity')::integer;
    exception when others then
      raise exception 'Data produk dalam keranjang tidak valid.';
    end;

    if v_quantity is null or v_quantity < 1 or v_quantity > 50 then
      raise exception 'Jumlah produk tidak valid.';
    end if;

    insert into public.order_items (
      order_id, product_id, product_name_snapshot, unit_price_snapshot, quantity
    )
    select v_order_id, p.id, p.name, p.price, v_quantity
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

  select o.total_amount
    into v_total
  from public.orders o
  where o.id = v_order_id;

  return query
    select v_order_id, v_order_number, v_delivery_date, v_total;
end;
$$;

revoke all on function public.create_guest_order(text, text, text, text, text, text, jsonb, text)
  from public;

grant execute on function public.create_guest_order(text, text, text, text, text, text, jsonb, text)
  to anon, authenticated;

notify pgrst, 'reload schema';

commit;

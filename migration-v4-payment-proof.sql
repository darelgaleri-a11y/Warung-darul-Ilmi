-- WARUNG DARUL ILMI v0.8: unggah bukti transfer untuk pesanan tamu
-- Jalankan SATU KALI setelah migration v2 dan v3 sukses.
begin;

create extension if not exists pgcrypto with schema extensions;

alter table public.orders
  add column if not exists guest_access_token_hash bytea;

-- Private bucket: file tidak dapat dibaca publik.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public=false, file_size_limit=5242880,
  allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];

-- Periksa format path order_uuid/token_hex/filename sebelum Storage menerima file.
create or replace function public.can_upload_guest_payment_proof(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v_order_id uuid; v_token text;
begin
  if array_length(string_to_array(p_name,'/'),1) <> 3 then return false; end if;
  if split_part(p_name,'/',1) !~* '^[0-9a-f-]{36}$' then return false; end if;
  v_token := split_part(p_name,'/',2);
  if v_token !~ '^[0-9a-f]{64}$' then return false; end if;
  v_order_id := split_part(p_name,'/',1)::uuid;
  return exists (
    select 1 from public.orders o
    where o.id=v_order_id
      and o.guest_access_token_hash=extensions.digest(v_token,'sha256')
      and o.payment_state in ('unpaid'::public.payment_status,'rejected'::public.payment_status)
  );
exception when others then return false;
end;
$$;
revoke all on function public.can_upload_guest_payment_proof(text) from public;
grant execute on function public.can_upload_guest_payment_proof(text) to anon, authenticated;

-- Recreate guest order RPC with one additional capability token argument.
drop function if exists public.create_guest_order(text,text,text,text,text,text,jsonb);
create function public.create_guest_order(
  p_guest_name text,
  p_guest_gender text,
  p_guest_dormitory text,
  p_guest_class text,
  p_guest_phone text,
  p_customer_note text,
  p_items jsonb,
  p_access_token text
)
returns table (order_id uuid, order_number text, delivery_date date, total_amount bigint)
language plpgsql security definer set search_path = '' as $$
declare
  v_order_id uuid; v_order_number text; v_delivery_date date; v_total bigint;
  v_item jsonb; v_product_id bigint; v_quantity integer; v_count integer := 0;
begin
  if length(trim(coalesce(p_guest_name,''))) < 2 then raise exception 'Nama santri wajib diisi.'; end if;
  if p_guest_gender not in ('Putra','Putri') then raise exception 'Kategori santri tidak valid.'; end if;
  if length(trim(coalesce(p_guest_dormitory,''))) < 1 or length(trim(coalesce(p_guest_class,''))) < 1 then raise exception 'Asrama dan kelas wajib diisi.'; end if;
  if p_access_token is null or p_access_token !~ '^[0-9a-f]{64}$' then raise exception 'Token akses pesanan tidak valid.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 30 then raise exception 'Keranjang kosong atau jumlah item melebihi batas.'; end if;

  insert into public.orders (customer_id,guest_name,guest_gender,guest_dormitory,guest_class,guest_phone,customer_note,delivery_date,guest_access_token_hash)
  values (null,trim(p_guest_name),p_guest_gender,trim(p_guest_dormitory),trim(p_guest_class),nullif(trim(coalesce(p_guest_phone,'')),''),nullif(trim(coalesce(p_customer_note,'')),''),public.next_delivery_date(),extensions.digest(p_access_token,'sha256'))
  returning id, order_number, delivery_date into v_order_id,v_order_number,v_delivery_date;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::bigint;
    v_quantity := (v_item->>'quantity')::integer;
    if v_quantity is null or v_quantity < 1 or v_quantity > 50 then raise exception 'Jumlah produk tidak valid.'; end if;
    insert into public.order_items(order_id,product_id,product_name_snapshot,unit_price_snapshot,quantity)
    select v_order_id,p.id,p.name,p.price,v_quantity from public.products p where p.id=v_product_id and p.is_available=true;
    if not found then raise exception 'Produk ID % tidak ditemukan atau tidak tersedia.',v_product_id; end if;
    v_count := v_count + 1;
  end loop;
  if v_count=0 then raise exception 'Tidak ada item pesanan yang valid.'; end if;
  select o.total_amount into v_total from public.orders o where o.id=v_order_id;
  return query select v_order_id,v_order_number,v_delivery_date,v_total;
end;
$$;
revoke all on function public.create_guest_order(text,text,text,text,text,text,jsonb,text) from public;
grant execute on function public.create_guest_order(text,text,text,text,text,text,jsonb,text) to anon,authenticated;

-- Tamu hanya boleh membuat catatan pembayaran untuk order yang token aksesnya cocok.
drop policy if exists "payments_insert_guest_token" on public.payment_records;
grant insert on public.payment_records to anon;
create policy "payments_insert_guest_token" on public.payment_records for insert to anon,authenticated
with check (
  status='pending_verification'::public.payment_status and verified_by is null and verified_at is null
  and exists (
    select 1 from public.orders o where o.id=order_id
      and o.guest_access_token_hash is not null
      and proof_url is not null
      and split_part(proof_url,'/',1)=o.id::text
      and public.can_upload_guest_payment_proof(proof_url)
      and amount=o.total_amount
      and o.payment_state in ('unpaid'::public.payment_status,'rejected'::public.payment_status)
  )
);

-- Storage upload policy: token pada path harus cocok dengan hash yang tersimpan di order.
drop policy if exists "guest_upload_payment_proof_by_token" on storage.objects;
create policy "guest_upload_payment_proof_by_token" on storage.objects for insert to anon,authenticated
with check (bucket_id='payment-proofs' and public.can_upload_guest_payment_proof(name));

-- Hanya staf yang berwenang pada jalur pesanan dapat membaca file melalui signed URL.
drop policy if exists "staff_read_scoped_payment_proofs" on storage.objects;
create policy "staff_read_scoped_payment_proofs" on storage.objects for select to authenticated
using (
  bucket_id='payment-proofs'
  and split_part(name,'/',1) ~* '^[0-9a-f-]{36}$'
  and exists (
    select 1 from public.orders o where o.id=split_part(name,'/',1)::uuid
      and public.can_access_order_gender(o.guest_gender)
  )
);

commit;

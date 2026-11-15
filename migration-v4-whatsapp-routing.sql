-- Warung Darul Ilmi v1.0: nomor WhatsApp terpisah untuk jalur kasir Putra dan Putri.
-- Nomor lama whatsapp_number tetap dipertahankan sebagai fallback agar kompatibel.

begin;

alter table public.store_settings
  add column if not exists whatsapp_number_putra text,
  add column if not exists whatsapp_number_putri text;

comment on column public.store_settings.whatsapp_number_putra is
  'Nomor WhatsApp tujuan pesanan pelanggan kategori Putra, format kode negara 62.';
comment on column public.store_settings.whatsapp_number_putri is
  'Nomor WhatsApp tujuan pesanan pelanggan kategori Putri, format kode negara 62.';

commit;

-- Meminta PostgREST memuat ulang cache skema setelah kolom baru ditambahkan.
notify pgrst, 'reload schema';

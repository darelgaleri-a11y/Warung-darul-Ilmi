-- Warung Darul Ilmi: persistent, replaceable store logo
-- Public reads are allowed by the bucket setting. Uploads are performed only
-- by the authenticated Super Admin Edge Function using the service role key.
begin;

alter table public.store_settings
  add column if not exists brand_logo_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'store-assets',
  'store-assets',
  true,
  2097152,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

commit;

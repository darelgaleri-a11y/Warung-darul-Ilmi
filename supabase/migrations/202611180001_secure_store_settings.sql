-- Warung Darul Ilmi v1.2.6
-- Jalankan SATU KALI setelah migrasi sebelumnya (v1-v5).
-- Aplikasi browser tidak lagi boleh UPDATE store_settings secara langsung.
-- Penyimpanan hanya dilakukan Edge Function dengan service role setelah verifikasi password.
begin;
revoke update on table public.store_settings from anon, authenticated;
notify pgrst, 'reload schema';
commit;

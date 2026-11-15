# Warung Darul Ilmi v0.9 — Jadwal & Pengecualian Tanggal

## Fitur
- Semua fitur katalog v0.8 tetap dipertahankan.
- Super Admin dapat mengatur hari pengiriman mingguan.
- Super Admin dapat menambahkan tanggal libur (menutup pengiriman) atau tanggal pengiriman khusus.
- Pengecualian tanggal menggunakan tabel `public.delivery_date_overrides` yang sudah tersedia sejak database v1.
- Aturan tanggal khusus mengesampingkan jadwal mingguan melalui fungsi `public.next_delivery_date()`.

## Instalasi
1. Ekstrak ZIP ke folder baru.
2. Salin `.env.local` dari instalasi v0.8 ke folder ini. Jangan menyalin atau membagikan `service_role` key.
3. Jalankan `npm install` lalu `npm run dev`.
4. Login sebagai Super Admin, buka menu Pengaturan, lalu bagian Pengecualian tanggal pengiriman.

## Database
Tidak memerlukan migrasi SQL baru. Fitur ini menggunakan tabel `delivery_date_overrides` dan kebijakan RLS yang sudah ada pada database v1. Jika tabel tersebut tidak ada, pastikan database v1 telah diterapkan.

## Catatan
- Tanggal yang ditambahkan sebagai libur akan menutup pengiriman pada tanggal itu, meskipun hari tersebut aktif pada jadwal mingguan.
- Tanggal pengiriman khusus dapat mengaktifkan pengiriman meskipun hari itu tidak aktif pada jadwal mingguan.
- Fungsi `next_delivery_date()` menghitung tanggal mulai BESOK sesuai implementasi database saat ini.

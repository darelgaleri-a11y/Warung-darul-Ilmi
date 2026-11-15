# Warung Darul Ilmi — versi 0.3 (Supabase Auth)

## Fitur pada versi ini
- Koneksi ke Supabase.
- Login email/password menggunakan Supabase Auth.
- Pendaftaran akun pelanggan.
- Profil otomatis dibuat oleh trigger database.
- Menu Kasir hanya ditampilkan untuk role `cashier` dan `super_admin`.
- Menu Super Admin dan Pengaturan hanya ditampilkan untuk role `super_admin`.
- Tombol keluar akun.

## Instalasi dan konfigurasi
1. Ekstrak ZIP dan buka folder `warung-darul-ilmi` di VS Code.
2. Buat `.env.local` di folder utama:
   ```
   VITE_SUPABASE_URL=https://PROJECT-REF.supabase.co
   VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
   ```
3. Jalankan:
   ```
   npm install
   npm run dev
   ```

## Akun pertama
- Login memakai email/password akun super admin yang sudah dibuat di Supabase Authentication.
- Pastikan `public.profiles.role` untuk akun pemilik bernilai `super_admin`.
- Pendaftaran melalui layar aplikasi membuat akun dengan role default `customer`.
- Jika konfirmasi email diaktifkan di Supabase, pelanggan harus membuka email konfirmasi sebelum dapat login.

## Membuat akun kasir
Buat akun kasir melalui Supabase Authentication, lalu ubah role-nya oleh super admin melalui SQL Editor:
```
update public.profiles
set role = 'cashier'
where id = (
  select id from auth.users where email = 'EMAIL_KASIR'
);
```
Jangan ubah role lewat browser pelanggan.

## Batasan yang masih berlaku
- Pesanan masih disimpan di localStorage pada browser, belum tersinkron lintas perangkat.
- Menu masih data contoh.
- Jadwal pelanggan pada form lama belum diganti menjadi tanggal otomatis dari database.
- Tampilan role bukan pengganti RLS. RLS tetap menjadi pengaman akses data di server/database.
- Tahap selanjutnya: migrasi katalog, pesanan, item pesanan, dan jadwal pengiriman ke Supabase.

## Keamanan
- Jangan masukkan `service_role` atau secret key ke frontend.
- Jangan commit `.env.local`; file ini dikecualikan oleh `.gitignore`.

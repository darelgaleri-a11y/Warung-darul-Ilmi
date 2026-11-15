# Warung Darul Ilmi — v0.4 (Guest checkout + staff login)

## Perubahan utama
- Halaman katalog pelanggan langsung terbuka tanpa login.
- Pelanggan tidak memiliki menu daftar akun atau login.
- Login hanya tersedia melalui tombol "Login Staf".
- Login staf memakai Supabase Auth; menu kasir hanya untuk role `cashier`/`super_admin`, menu super admin/pengaturan hanya untuk `super_admin`.
- Form pelanggan tidak lagi meminta pilihan jam/jadwal. Jadwal dijelaskan sebagai penentuan otomatis oleh admin.

## Instalasi
1. Ekstrak ZIP dan buka folder `warung-darul-ilmi`.
2. Pastikan file `.env.local` tetap ada di folder utama:
   ```
   VITE_SUPABASE_URL=https://PROJECT-REF.supabase.co
   VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
   ```
3. Jalankan `npm install`, lalu `npm run dev`.

## Penting
- Versi ini memperbaiki alur akses pelanggan dan login petugas.
- Pesanan masih disimpan di localStorage dan belum tersinkron lintas perangkat.
- Katalog masih data contoh.
- Tanggal pengiriman aktual dan penyimpanan pesanan online akan diaktifkan pada tahap integrasi database berikutnya. Saat ini form hanya menyatakan jadwal otomatis; belum menampilkan tanggal hasil perhitungan database.
- RLS database tetap wajib dan harus diverifikasi sebelum aplikasi dipakai publik.
- Jangan gunakan service_role/secret key di frontend.

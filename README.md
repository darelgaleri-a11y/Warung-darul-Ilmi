# Warung Darul Ilmi v0.6

Melanjutkan v0.5 dengan pengaturan rekening, jadwal mingguan, dan pembatasan data kasir Putra/Putri di PostgreSQL Row Level Security (RLS).

## PENTING SEBELUM MENJALANKAN

1. Simpan salinan folder v0.5.
2. Jalankan `migration-v3-operations-security.sql` satu kali di Supabase SQL Editor, setelah migration v2 guest checkout berhasil.
3. Pastikan minimal satu hari aktif pada `delivery_weekdays`, agar fungsi `next_delivery_date()` dapat menentukan tanggal.
4. Setelah migration v3, setiap profil dengan role `cashier` wajib mempunyai `cashier_gender` bernilai `Putra` atau `Putri`.
5. Salin `.env.local` milik v0.5 ke folder versi ini. Jangan pernah memasukkan `service_role`/secret key ke browser.

## Mengatur jalur akun kasir

Buat akun kasir melalui Supabase Authentication terlebih dahulu. Lalu jalankan SQL berikut di SQL Editor, ganti email dan jalur sesuai petugas:

```sql
update public.profiles
set role = 'cashier', cashier_gender = 'Putra'
where id = (select id from auth.users where email = 'email-kasir-putra@example.com');

update public.profiles
set role = 'cashier', cashier_gender = 'Putri'
where id = (select id from auth.users where email = 'email-kasir-putri@example.com');
```

Untuk Super Admin, role tetap `super_admin`. Kasir tidak dapat mengubah sendiri role atau jalur aksesnya. RLS membatasi pesanan, item, catatan pembayaran, dan riwayat sesuai gender yang ditugaskan.

## Menjalankan aplikasi

```bash
npm install
npm run dev
```

## Perubahan v0.6

- Super Admin dapat menyimpan nama toko, WhatsApp, nama bank, nomor rekening, nama pemilik rekening, dan instruksi transfer.
- Informasi rekening ditampilkan kepada pelanggan dan dapat disertakan pada pesan WhatsApp pesanan.
- Super Admin dapat mengaktifkan/nonaktifkan hari pengiriman mingguan.
- Halaman pelanggan menampilkan perkiraan tanggal pengiriman terdekat dari fungsi database.
- Kasir menampilkan jalur gender yang ditugaskan.
- RLS di database membatasi akses kasir untuk pesanan sesuai `cashier_gender`, termasuk item pesanan, pembayaran, dan riwayat.

## Batasan yang masih ada

- Bukti transfer belum mempunyai alur upload ke Supabase Storage.
- Pengelolaan pengecualian tanggal khusus (misalnya hari libur) belum disediakan di UI; tabel `delivery_date_overrides` sudah tersedia dari database v1.
- Distribusi, cetak tiket dapur, penyelesaian shift, dan ekspor XLSX asli masih perlu dikerjakan.
- Belum dilakukan uji beban 1.000 pengguna bersamaan.
- Build perlu diuji di komputer pengembang dengan `npm install` dan `npm run build` sebelum dipakai operasional.

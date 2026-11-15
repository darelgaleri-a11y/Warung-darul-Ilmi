# Warung Darul Ilmi v0.5

Versi ini melanjutkan fondasi React + Vite + Supabase dari v0.4 dan mulai menghubungkan katalog, checkout tamu, antrean kasir, status pesanan, serta pengaturan WhatsApp.

## Sebelum menjalankan

1. Pastikan SQL Database v1 sudah dijalankan pada proyek Supabase.
2. Jalankan `migration-v2-guest-checkout.sql` satu kali melalui Supabase SQL Editor. File ini juga tersedia terpisah.
3. Pastikan ada produk aktif pada tabel `products` dan kategori aktif pada `categories`.
4. Pastikan akun petugas sudah ada di Authentication dan profilnya memiliki role `cashier` atau `super_admin`.
5. Salin `.env.example` menjadi `.env.local`, lalu isi URL dan publishable key Supabase.

Contoh `.env.local`:

```env
VITE_SUPABASE_URL=https://PROJECT-REF.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxxxxxxxx
```

Jangan pernah memasukkan `service_role` atau secret key ke aplikasi browser.

## Menjalankan

```bash
npm install
npm run dev
```

Buka alamat lokal yang ditampilkan Vite. Jika `.env.local` diubah, hentikan server dengan Ctrl+C lalu jalankan kembali `npm run dev`.

## Yang sudah diintegrasikan pada v0.5

- Katalog kategori dan produk dibaca dari Supabase.
- Checkout pelanggan tanpa akun menggunakan RPC `create_guest_order`.
- Nama/nomor pesanan, total, dan tanggal pengiriman berasal dari hasil database.
- Pesanan baru diteruskan ke WhatsApp setelah penyimpanan database berhasil (jika nomor WhatsApp sudah diatur).
- Kasir dan super admin membaca daftar pesanan online.
- Status pesanan dan status pembayaran diperbarui di tabel `orders`.
- Super Admin melihat rekap Putra/Putri dan mengekspor CSV yang dapat dibuka di Excel.
- Nomor WhatsApp toko dapat disimpan ke `store_settings`.

## Batasan yang masih diketahui

- Data rekening belum tersedia di skema database v1; jangan menganggap bagian rekening sudah aktif.
- Pengaturan cut-off dan distribusi terjadwal belum diimplementasikan.
- Pemisahan akses kasir Putra/Putri belum ditegakkan di tingkat database. Saat ini kasir dapat memfilter kedua kategori; perlu migrasi role/scope kasir sebelum dipakai operasional.
- Bukti transfer belum diunggah dan payment gateway belum terhubung. Verifikasi pembayaran masih manual dengan mengubah status oleh staf.
- Ekspor saat ini CSV kompatibel Excel, belum file XLSX asli.
- Realtime bergantung pada konfigurasi Supabase Realtime untuk tabel `orders`; tombol muat ulang tetap tersedia.
- Enam HTML asli merupakan acuan desain dan alur. Versi ini belum mereplikasi semua detail visual dan seluruh fitur adminnya.
- Belum diuji untuk 1.000 pengguna aktif bersamaan. Lakukan uji beban dan penyesuaian infrastruktur sebelum peluncuran besar.

## Keamanan

Gunakan Supabase publishable key saja pada frontend. Kebijakan RLS dan fungsi RPC menjadi batas keamanan utama. Uji akun anon, kasir, dan super admin sebelum membuka aplikasi untuk umum.

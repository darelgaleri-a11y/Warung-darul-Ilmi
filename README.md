# Warung Darul Ilmi — versi 0.2 (uji koneksi Supabase)

## Yang berubah
- Menambahkan Supabase JavaScript client.
- Menambahkan konfigurasi environment lokal.
- Menampilkan status uji koneksi ke tabel `store_settings`.
- Data pesanan pada versi ini MASIH disimpan di localStorage. Sinkronisasi pesanan lintas perangkat dan login belum diaktifkan pada tahap ini.

## Persiapan
1. Ekstrak ZIP.
2. Buka folder `warung-darul-ilmi` di VS Code.
3. Buat file baru bernama `.env.local` di folder utama (sejajar dengan `package.json`).
4. Salin isi `.env.example` ke `.env.local`.
5. Ganti nilai contoh dengan Project URL dan Publishable Key dari Supabase:
   ```
   VITE_SUPABASE_URL=https://PROJECT-REF.supabase.co
   VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
   ```
6. Simpan file. Jangan kirim `service_role` atau secret key ke browser/chat.
7. Di terminal VS Code jalankan:
   ```
   npm install
   npm run dev
   ```
8. Jika server Vite sudah berjalan sebelum `.env.local` dibuat/diubah, hentikan dengan Ctrl+C lalu jalankan `npm run dev` lagi.

## Hasil yang diharapkan
Di bagian atas aplikasi akan tampil:
- "Terhubung ke Supabase..." jika koneksi dan pembacaan `store_settings` berhasil.
- Pesan konfigurasi/error jika belum berhasil.

## Penting
- `.env.local` tidak boleh di-commit ke Git. Sudah dikecualikan oleh `.gitignore`.
- Publishable key memang digunakan di frontend; keamanan data tetap bergantung pada RLS dan kebijakan database.
- Jangan gunakan service_role key di aplikasi React.
- Tahap berikutnya adalah autentikasi dan pemindahan menu/pesanan dari localStorage ke Supabase. Dashboard kasir/admin harus dikunci berdasarkan role sebelum dipakai operasional.

## Menjalankan aplikasi
```
npm install
npm run dev
```

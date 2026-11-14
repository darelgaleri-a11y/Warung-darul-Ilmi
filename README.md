# Warung Darul Ilmi — versi awal

Aplikasi web React + Vite untuk uji alur pemesanan, kasir, dan ringkasan admin.

## Kebutuhan
- Node.js versi LTS
- VS Code
- Koneksi internet saat pertama kali memasang dependensi

## Menjalankan aplikasi
1. Ekstrak ZIP ini.
2. Buka folder `warung-darul-ilmi` di VS Code.
3. Buka Terminal > New Terminal.
4. Jalankan `npm install`.
5. Jalankan `npm run dev`.
6. Buka alamat lokal yang ditampilkan Vite (biasanya `http://localhost:5173`).

## Konfigurasi WhatsApp
Buka `src/App.jsx`, cari `WHATSAPP_ADMIN`, lalu ganti nilainya dengan nomor WhatsApp admin format internasional tanpa tanda plus atau spasi. Contoh format: `628xxxxxxxxxx`.

Nomor juga bisa dimasukkan dari halaman Pengaturan aplikasi. Untuk pengujian, isi nomor milik admin yang memang akan menerima pesanan.

## Catatan penting versi awal
- Menu, kelas, asrama, dan jadwal yang tampil adalah DATA CONTOH. Ubah setelah data resmi tersedia.
- Data pesanan disimpan di localStorage browser, bukan database online. Artinya, data tidak otomatis tersinkron antar perangkat/komputer.
- Halaman kasir dan super admin pada tahap ini adalah prototipe lokal, belum dilindungi autentikasi/otorisasi.
- Status pembayaran dapat diubah manual untuk simulasi. Belum ada integrasi pembayaran otomatis.
- Pengiriman pesanan membuka WhatsApp dengan teks pesanan terisi. Pengguna tetap harus menekan tombol kirim di WhatsApp.
- Jangan gunakan versi ini untuk operasional nyata sebelum database online, akun dan hak akses, serta alur verifikasi pembayaran disiapkan.

## Struktur
- `src/App.jsx` — alur aplikasi dan komponen
- `src/styles.css` — desain responsif
- `src/main.jsx` — entry point React
- `index.html` — dokumen utama

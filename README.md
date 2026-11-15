# Warung Darul Ilmi v1.0 — WhatsApp Kasir Putra/Putri

## Fitur baru
- Pesanan pelanggan kategori Putra diarahkan ke nomor WhatsApp Kasir Putra.
- Pesanan pelanggan kategori Putri diarahkan ke nomor WhatsApp Kasir Putri.
- Nomor WhatsApp Admin Umum yang lama tetap tersedia sebagai nomor cadangan jika nomor jalur terkait belum diisi.
- Pesan WhatsApp memuat rincian pesanan, total, rekening transfer, dan instruksi mengirim foto/screenshot bukti transfer di chat yang sama.
- Bukti transfer tetap dikirim langsung melalui WhatsApp; aplikasi tidak menerima atau menyimpan file bukti transfer.

## Instalasi / pembaruan
1. Ekstrak ZIP ke folder baru, jangan menimpa folder versi lama.
2. Salin file `.env.local` dari instalasi v0.9.1. Jangan membagikan `service_role` key.
3. Buka folder baru di VS Code.
4. Jalankan `npm install`, lalu `npm run dev`.

## Migrasi database v4 (wajib satu kali)
1. Buka Supabase → SQL Editor → New query.
2. Buka file `migration-v4-whatsapp-routing.sql` dari ZIP ini, salin seluruh isinya, lalu jalankan.
3. Pastikan muncul `Success`.
4. Tidak perlu mengulang migrasi v1, v2, atau v3.

## Pengaturan nomor WhatsApp
Login sebagai Super Admin → Pengaturan → Informasi toko & pembayaran. Isi:
- WhatsApp Kasir Putra, contoh format `628xxxxxxxxxx`.
- WhatsApp Kasir Putri, contoh format `628xxxxxxxxxx`.
- WhatsApp Admin Umum (cadangan), opsional.

Gunakan nomor aktif dengan WhatsApp. Jangan gunakan tanda `+`, spasi, atau tanda baca.

## Pengujian
- Isi nomor WhatsApp Putra dan Putri yang berbeda.
- Buat pesanan percobaan dengan kategori Putra; pastikan tautan membuka chat nomor Putra.
- Buat pesanan percobaan dengan kategori Putri; pastikan tautan membuka chat nomor Putri.
- Pastikan pesan memuat nomor pesanan, identitas, rincian barang, total, rekening, dan instruksi mengirim bukti transfer melalui chat.
- Pastikan pelanggan tetap harus menekan tombol Kirim di WhatsApp dan melampirkan bukti transfer sendiri.
- Uji nomor cadangan dengan mengosongkan nomor salah satu jalur (gunakan pesanan percobaan).

## Catatan penting
- Tautan WhatsApp hanya membuka chat dengan teks yang sudah disiapkan. Aplikasi tidak mengirim pesan otomatis. Pelanggan harus menekan Kirim.
- Konfirmasi pembayaran tetap dilakukan petugas melalui WhatsApp. Status pembayaran/pesanan di aplikasi dikelola petugas sesuai alur operasional.
- Fitur token akses pesanan tamu dari v0.9.1 dan fitur kalender pengiriman tetap dipertahankan.

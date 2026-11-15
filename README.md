# Warung Darul Ilmi v1.1.1 — Perbaikan Kasir, Distribusi & Laporan

## Perbaikan dari v1.1
- Query antrean kasir diberi pembatas `guest_gender` sesuai `profiles.cashier_gender`, selain tetap dilindungi RLS Supabase. Kasir tanpa jalur Putra/Putri akan ditolak dari pemuatan antrean (fail-closed) dan mendapat petunjuk pengaturan.
- Statistik kasir dan halaman distribusi menggunakan data yang sudah dibatasi sesuai jalur kasir. Super Admin tetap melihat kedua jalur.
- Kasir tidak dapat mengubah pesanan dari jalur lain melalui antarmuka; server tetap menjadi pengaman utama melalui RLS.
- Filter tanggal dan kategori distribusi tetap tersedia; daftar dikelompokkan secara konsisten menurut Putra/Putri dan asrama.
- Pengamanan tambahan mencegah pesanan ditandai diserahkan sebelum status `ready`.
- Pencetakan tiket dapur menggunakan hasil filter tanggal dan kategori yang sedang dipilih.
- Ekspor Excel memiliki tiga lembar: Pesanan, Rincian Item, dan Ringkasan Putra/Putri.
- Pemuatan pesanan menggunakan pagination hingga 20.000 baris agar laporan tidak berhenti diam-diam pada 300 pesanan.
- Alur pembayaran tetap melalui WhatsApp: pelanggan mengirim bukti transfer di chat dan kasir memeriksanya di WhatsApp. Aplikasi tidak mengunggah atau memverifikasi bukti transfer.

## Instalasi / pembaruan
1. Ekstrak ZIP ke folder baru, jangan menimpa v1.1.
2. Salin `.env.local` dari folder v1.1.
3. Buka folder baru melalui VS Code.
4. Jalankan `npm install`, lalu `npm run dev`.

## Database
Tidak memerlukan migrasi SQL baru. Pertahankan migrasi v1 sampai v4 yang sudah berhasil dijalankan. Jangan jalankan ulang migrasi tersebut.

## Penting: pengaturan jalur kasir
Di Supabase Table Editor → `profiles`, pastikan setiap akun `cashier` memiliki `cashier_gender` yang tepat: `Putra` atau `Putri`. Akun `super_admin` tidak perlu nilai ini. Jangan mengubah role akun melalui aplikasi pelanggan.

## Checklist pengujian
- Login Kasir Putra hanya menampilkan pesanan Putra pada antrean dan distribusi.
- Login Kasir Putri hanya menampilkan pesanan Putri pada antrean dan distribusi.
- Akun kasir tanpa `cashier_gender` tidak memperoleh antrean sampai diperbaiki Super Admin.
- Super Admin melihat pesanan Putra dan Putri serta dapat memfilter masing-masing.
- Filter tanggal pengiriman dan kategori santri pada distribusi mengubah daftar dan statistik.
- Pesanan dikelompokkan berdasarkan kategori santri dan asrama.
- Cetak semua tiket dan cetak tiket satu pesanan berhasil. Jika popup diblokir, izinkan popup untuk situs aplikasi.
- Tombol penyerahan nonaktif sebelum status `Siap diserahkan` dan aktif sesudahnya.
- Ekspor Excel menghasilkan tiga lembar dan jumlahnya sesuai data yang tampil.
- Pelanggan mengirim bukti transfer melalui WhatsApp; tidak ada unggah bukti ke aplikasi.
- Kasir memeriksa transfer di WhatsApp dan mengubah status operasional melalui aplikasi.

## Catatan verifikasi
Build produksi perlu dijalankan pada komputer pengguna dengan `npm run build`. Pada lingkungan pembuatan paket ini, pemasangan dependensi mengalami timeout sehingga build produksi belum dapat dikonfirmasi di sini.

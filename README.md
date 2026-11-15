# Warung Darul Ilmi v0.7

Melanjutkan v0.6. Versi ini menambahkan ruang distribusi/dapur dan laporan Excel asli (.xlsx).

## Sebelum memasang

1. Simpan folder v0.6 sebagai cadangan.
2. Ekstrak folder versi ini ke lokasi baru.
3. Salin `.env.local` dari v0.6 ke folder `warung-darul-ilmi` versi ini.
4. Tidak ada migrasi SQL tambahan pada v0.7. Versi ini memakai tabel dan kebijakan yang sudah dibuat pada database v1, migrasi v2, dan migrasi v3.
5. Jangan pernah menaruh `service_role`/secret key di `.env.local` frontend. Gunakan hanya URL dan publishable/anon key.

## Menjalankan

```bash
npm install
npm run dev
```

Untuk pemeriksaan build produksi:

```bash
npm run build
```

## Fitur v0.7

- Menu **Distribusi & Dapur** untuk staf dan Super Admin.
- Filter pesanan berdasarkan tanggal pengiriman dan kategori Putra/Putri.
- Rekap jumlah pesanan, jumlah item, dan nilai pesanan pada tanggal terpilih.
- Pengelompokan pesanan berdasarkan kategori santri dan asrama.
- Cetak tiket dapur per pesanan atau seluruh pesanan yang sedang difilter.
- Tombol tandai pesanan sudah diserahkan; perubahan disimpan ke tabel `orders` dan tetap tunduk pada RLS.
- Ekspor laporan `.xlsx` dengan dua lembar: `Pesanan` dan `Rincian Item`.

## Catatan

- Cetak tiket menggunakan dialog cetak browser. Izinkan pop-up untuk situs aplikasi jika browser memblokir jendela cetak.
- Data distribusi mengikuti pesanan yang berhasil dimuat oleh akun yang sedang login. Kasir Putra/Putri tetap dibatasi oleh RLS.
- Ekspor XLSX memuat data yang tersedia pada daftar pesanan aplikasi (maksimal 300 pesanan terakhir pada query saat ini). Untuk laporan periode panjang, perlu fitur filter periode/paginasi pada iterasi berikutnya.
- Upload bukti transfer pelanggan belum termasuk v0.7. Akan dibuat pada iterasi berikutnya dengan token akses pesanan tamu agar bukti transfer tidak dapat dilihat atau diganti oleh orang lain.
- Belum ada uji beban 1.000 pengguna bersamaan. Jalankan `npm run build` dan uji alur di staging sebelum penggunaan operasional.

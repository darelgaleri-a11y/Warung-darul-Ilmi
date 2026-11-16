# Warung Darul Ilmi v1.2.1 — Format matriks laporan Excel

## Fokus perbaikan
- Pemisahan jalur Kasir Putra/Putri diperketat di database melalui migration v5. Migration menghapus seluruh policy lama pada `orders` dan `order_items` sebelum membuat policy baru yang membatasi berdasarkan profil kasir. Ini mencegah policy lama yang bersifat permisif membuka data lintas jalur.
- Super Admin tetap dapat melihat kedua jalur.
- Super Admin dapat menetapkan jalur akun kasir melalui Pengaturan → Pembagian akun kasir. Tidak perlu mengedit tabel `profiles` secara manual.
- Normalisasi gender menangani spasi dan perbedaan kapitalisasi.
- Halaman Dapur & Distribusi otomatis memilih tanggal pengiriman yang memang memiliki pesanan (tanggal mendatang terdekat; jika tidak ada, tanggal pesanan terbaru). Kasir hanya dapat memilih jalurnya sendiri.
- Filter tanggal dan kategori memengaruhi daftar, statistik, pengelompokan asrama, serta cetak tiket.
- Cetak tiket menggunakan iframe tersembunyi sehingga tidak bergantung pada izin popup browser.
- Ekspor Excel memiliki filter rentang tanggal dan tiga lembar: Pesanan (format matriks santri × produk), Rincian Item, dan Ringkasan Putra/Putri.
- Lembar Pesanan menampilkan satu baris per pesanan santri: Nama Santri, Kelas, Asrama, Kategori, Tanggal Pengiriman, Nomor Pesanan, lalu kolom dinamis per produk. Isi sel berupa jumlah item; angka 0 berarti produk tidak dipesan. Total dan status pesanan ditempatkan di kolom paling kanan.
- Lembar Rincian Item dan Ringkasan dipertahankan seperti versi 1.2.
- Pembayaran dan pengiriman bukti transfer tetap dilakukan melalui WhatsApp. Tidak ada unggah bukti transfer atau verifikasi pembayaran di aplikasi.

## Instalasi
1. Ekstrak ZIP ke folder baru, jangan menimpa v1.1.1.
2. Salin `.env.local` dari folder v1.1.1.
3. Buka folder baru di VS Code.
4. Jalankan `npm install` lalu `npm run dev`.

## Database
Tidak ada migrasi SQL baru pada v1.2.1. Gunakan database yang sudah berhasil dipasang dan diuji pada v1.2. Jangan jalankan ulang migrasi v1–v5.

## Checklist uji v1.2.1
- [ ] Buka Super Admin → Ringkasan → pilih rentang tanggal yang berisi pesanan.
- [ ] Klik Ekspor Excel.
- [ ] Pada lembar Pesanan, pastikan kolom pertama adalah Nama Santri, Kelas, dan Asrama.
- [ ] Pastikan setiap produk yang muncul dalam rentang laporan memiliki kolom sendiri.
- [ ] Pastikan angka pada kolom produk cocok dengan jumlah yang dipesan oleh santri. Produk yang tidak dipesan berisi 0.
- [ ] Pastikan satu transaksi menghasilkan satu baris; transaksi santri yang sama pada nomor pesanan berbeda tetap menjadi baris terpisah.
- [ ] Pastikan filter tanggal memengaruhi hasil ekspor.
- [ ] Pastikan lembar Rincian Item dan Ringkasan tetap benar.

## Checklist uji wajib
- [ ] Jalankan migrasi v5 sekali dan pastikan `Success`.
- [ ] Super Admin dapat melihat daftar akun kasir pada Pengaturan.
- [ ] Atur satu akun ke Putra dan satu akun ke Putri.
- [ ] Kasir Putra hanya melihat pesanan Putra di antrean dan distribusi.
- [ ] Kasir Putri hanya melihat pesanan Putri di antrean dan distribusi.
- [ ] Super Admin tetap melihat kedua jalur.
- [ ] Distribusi otomatis memilih tanggal yang memiliki pesanan.
- [ ] Ganti tanggal distribusi; daftar dan statistik ikut berubah.
- [ ] Filter kategori Putra/Putri berfungsi untuk Super Admin.
- [ ] Pesanan dikelompokkan berdasarkan gender dan asrama.
- [ ] Cetak semua tiket dan cetak satu tiket berfungsi.
- [ ] Tombol serahkan nonaktif sebelum status Siap diserahkan dan aktif setelahnya.
- [ ] Ekspor Excel menghasilkan tiga lembar.
- [ ] Coba rentang tanggal laporan dan cocokkan jumlah pesanan.
- [ ] Pembayaran dan bukti transfer tetap berlangsung melalui WhatsApp.

## Catatan
Build produksi harus diverifikasi dengan `npm run build` di komputer pengguna. Jangan menggunakan v1.1.1 untuk operasional sampai pemisahan kasir dan alur distribusi v1.2 lolos pengujian.

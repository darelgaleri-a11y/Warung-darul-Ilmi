# Warung Darul Ilmi v1.1 — Alur Kasir & Distribusi

## Perubahan dari v1.0
- Halaman kasir difokuskan pada status operasional pesanan, bukan verifikasi pembayaran.
- Kontrol status pembayaran dihapus dari daftar pesanan kasir dan Super Admin. Pemeriksaan transfer dan bukti transfer tetap dilakukan melalui WhatsApp.
- Ringkasan kasir menampilkan pesanan menunggu konfirmasi, sedang diproses, dan siap diserahkan.
- Status pesanan mengikuti tahapan: Menunggu → Dikonfirmasi → Diproses → Siap diserahkan → Sudah diserahkan. Pembatalan tersedia pada tahapan sebelum selesai.
- Tombol penyerahan di halaman Distribusi hanya aktif jika pesanan berstatus Siap diserahkan.
- Ekspor Excel berisi status pesanan, tanpa kolom verifikasi pembayaran.

## Instalasi / pembaruan
1. Ekstrak ZIP ke folder baru, jangan menimpa v1.0.
2. Salin `.env.local` dari folder v1.0.
3. Buka folder baru di VS Code.
4. Jalankan `npm install`, lalu `npm run dev`.

## Database
Tidak memerlukan migrasi SQL baru. Pertahankan migrasi v1, v2, v3, dan v4 yang sudah berhasil dijalankan. Jangan menjalankan ulang migrasi tersebut.

## Checklist pengujian
- Login Kasir Putra hanya menampilkan antrean Putra.
- Login Kasir Putri hanya menampilkan antrean Putri.
- Super Admin melihat antrean kedua jalur.
- Status Menunggu dapat diubah ke Dikonfirmasi atau Dibatalkan.
- Status Dikonfirmasi dapat diubah ke Diproses atau Dibatalkan.
- Status Diproses dapat diubah ke Siap diserahkan atau Dibatalkan.
- Status Siap diserahkan dapat diubah ke Sudah diserahkan atau Dibatalkan.
- Tombol Tandai diserahkan di halaman Distribusi tidak aktif sebelum status Siap diserahkan.
- Perubahan status tersimpan dan muncul setelah muat ulang.
- Bukti transfer tetap dikirim dan diperiksa melalui WhatsApp; tidak ada unggah atau verifikasi bukti transfer di aplikasi.
- Ekspor Excel memuat rincian pesanan dan status operasional.

## Catatan
Perubahan v1.1 hanya di sisi aplikasi; tidak mengubah tabel, fungsi, atau kebijakan keamanan Supabase. Pembatasan akses Putra/Putri tetap mengandalkan RLS yang telah dipasang pada migrasi v3.

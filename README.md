# Warung Darul Ilmi v0.8 — Bukti Transfer

Versi ini melanjutkan v0.7. Fitur utama: upload bukti transfer tamu ke Supabase Storage privat, catatan pembayaran `pending_verification`, tampilan bukti untuk staf dengan signed URL, dan verifikasi pembayaran melalui `payment_records`.

## PENTING SEBELUM MEMASANG

1. Cadangkan folder v0.7.
2. Jalankan `migration-v4-payment-proof.sql` **SATU KALI** di Supabase SQL Editor setelah migrasi v2 dan v3 berhasil. Jangan jalankan ulang jika sudah berhasil.
3. Salin `.env.local` dari v0.7 ke folder ini. Gunakan hanya Supabase URL dan publishable/anon key. Jangan gunakan `service_role`/secret key di frontend.
4. Jalankan `npm install`, lalu `npm run dev`.

## Cara uji

1. Buat pesanan baru sebagai pelanggan tanpa login.
2. Setelah pesanan tersimpan, unggah JPG/PNG/WEBP/PDF maksimal 5 MB pada panel Konfirmasi Pembayaran.
3. Login sebagai kasir sesuai jalur. Buka antrean dan tekan `Lihat bukti (tautan aman)`.
4. Ubah status pembayaran menjadi `Lunas` atau `Ditolak`. Status pembayaran pada order disinkronkan oleh trigger database dari `payment_records`.
5. Uji bahwa kasir Putra tidak dapat membuka bukti pesanan Putri, dan sebaliknya.

## Catatan keamanan dan batasan

- Bucket `payment-proofs` bersifat private. File tidak memakai URL publik.
- Order guest menerima token acak 256-bit dari browser; database hanya menyimpan hash SHA-256. Token disimpan di localStorage browser yang membuat pesanan agar pemilik dapat mengunggah bukti dari perangkat yang sama.
- Setelah bukti berhasil dikirim, akses unggah lokal dihapus. Jika data browser hilang atau pelanggan berpindah perangkat sebelum mengunggah, pelanggan perlu menghubungi admin untuk penanganan manual.
- Akses upload dibatasi untuk order berstatus `unpaid` atau `rejected`. File maksimal 5 MB dan hanya JPG/PNG/WEBP/PDF.
- Ini bukan payment gateway; kasir tetap memeriksa transfer secara manual.
- Build produksi belum dapat saya verifikasi di lingkungan pembuatan karena instalasi dependensi mengalami timeout. Jalankan `npm install` dan `npm run build` di komputer lokal; jangan anggap versi ini lolos build sampai perintah tersebut berhasil.

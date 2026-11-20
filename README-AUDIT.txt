AUDIT WARUNG DARUL ILMI
Repository: darelgaleri-a11y/Warung-darul-Ilmi
Branch: app

TEMUAN AUDIT KODE
1. package.json menggunakan tag "latest" untuk React, React DOM, Vite, dan plugin React. package-lock.json saat ini mengunci versi React 19.3.1, Vite 8.3.8, dan plugin React 6.3.0. Ketidaksesuaian ini membuat versi hasil instalasi bergantung pada cara/perintah yang dipakai. Patch menetapkan versi yang sama dengan lockfile sehingga `npm ci` menjadi reproducible.
2. Folder node_modules ikut tersimpan di repository. Itu membuat repository sangat besar dan mengikat artefak instalasi pada OS/arsitektur tertentu. Patch memperbarui .gitignore. Catatan: .gitignore tidak menghapus file node_modules yang sudah telanjur dilacak; instruksi opsional untuk mengeluarkannya dari Git ada di bawah.
3. Migrasi `202611200001_repair_guest_token_hash_storage.sql` mencoba mengubah guest_access_token_hash dari BYTEA ke TEXT. Kolom ini dipakai policy `payments_insert_guest_token`; PostgreSQL menolak perubahan tipe selama policy bergantung padanya. Ini sama dengan error yang sebelumnya Anda laporkan. Pertahankan tipe BYTEA. Migrasi `202611200002_fix_guest_checkout_keep_bytea.sql` adalah bentuk patch yang lebih tepat; jangan jalankan migrasi 202611200001 lagi.
4. Kode antarmuka menghitung beberapa tanggal dengan `new Date().toISOString().slice(0,10)` (UTC), sedangkan fungsi database next_delivery_date menghitung memakai timezone toko. Di sekitar tengah malam, tanggal browser dan tanggal toko bisa berbeda. Perlu penyelarasan timezone untuk audit tahap berikutnya.
5. `supabase/migrations/202611170001_initial_complete_schema.sql` menyatakan dirinya baseline untuk database BARU. Jangan jalankan di database produksi yang sudah punya skema/data.

FILE PATCH
- package.json: mengunci empat dependency yang sebelumnya memakai latest, tepat ke versi yang sudah tercatat pada package-lock.json.
- .gitignore: mengabaikan node_modules, dist, dan file .env lokal.

CARA MENJALANKAN
1. Ekstrak ZIP.
2. Salin package.json dan .gitignore dari ZIP ke folder lokal repository yang sudah Anda clone (backup dulu dua file lama).
3. Pastikan package-lock.json tetap dari branch `app` yang sama.
4. Buka terminal di folder proyek, lalu jalankan:
   npm ci
   npm run build
   npm run dev
5. Buka alamat localhost yang ditampilkan Vite.

HASIL YANG DIHARAPKAN
- `npm ci` selesai tanpa mengubah versi package karena package.json cocok dengan lockfile.
- `npm run build` membuat folder dist dan selesai tanpa error.
- `npm run dev` menjalankan aplikasi lokal seperti sebelumnya, dengan konfigurasi `.env.local` yang sudah ada.

PEMBERSIHAN NODE_MODULES DI GITHUB (OPSIONAL, TERPISAH)
Setelah memastikan build berhasil, jalankan dari root repository:
   git rm -r --cached node_modules
   git add .gitignore package.json
   git commit -m "chore: stabilize dependencies and ignore node_modules"
Ini hanya mengeluarkan node_modules dari Git index; folder lokal tetap ada. Periksa `git status` sebelum commit. Jika Anda tidak ingin mengubah repository, abaikan langkah opsional ini.

BATAS AUDIT
Ini audit statis berdasarkan kode yang dapat dibaca di branch `app`. Saya tidak mempunyai akses ke proyek Supabase Anda, data production, atau browser operasional. Karena itu patch ini tidak mengklaim telah membuktikan seluruh alur pesanan/pembayaran berjalan. Patch tidak berisi SQL dan tidak mengubah data, policy RLS, atau tipe token BYTEA.

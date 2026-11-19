$ErrorActionPreference = 'Stop'
$path = Join-Path (Get-Location) 'src\App.jsx'
if (!(Test-Path $path)) { throw 'src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek.' }
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
$old = @'
  async function loadOrders() {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return;
    setLoadingOrders(true);
    setOrders([]);
    if (profile.role === 'cashier' && !normalizeGender(profile.cashier_gender)) {
      setOrders([]);
      setNotice('Akun kasir belum diberi jalur Putra atau Putri. Minta Super Admin mengatur cashier_gender pada profil akun ini.');
      setLoadingOrders(false);
      return;
    }
    // Ambil dengan pagination agar antrean dan ekspor tidak diam-diam terpotong pada 300 baris.
    let allRows = [];
    let fetchError = null;
    for (let from = 0; from < 20000; from += 500) {
      let query = supabase.from('orders').select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)').order('created_at',{ascending:false}).range(from, from + 499);
      // Defense in depth: selain RLS di database, query kasir juga dibatasi pada jalurnya.
      if (profile.role === 'cashier') query = query.eq('guest_gender', normalizeGender(profile.cashier_gender));
      const {data,error} = await query;
      if (error) { fetchError = error; break; }
      allRows = allRows.concat(data || []);
      if (!data || data.length < 500) break;
    }
    if (fetchError) setNotice(`Gagal memuat pesanan: ${fetchError.message}`);
    else {
      setOrders(allRows.map(mapOrder));
      if (allRows.length >= 20000) setNotice('Data mencapai batas pemuatan 20.000 pesanan. Untuk laporan lebih lama, gunakan ekspor berdasarkan rentang tanggal pada pengembangan berikutnya.');
    }
    setLoadingOrders(false);
  }
'@
$new = @'
  async function loadOrders() {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return;
    setLoadingOrders(true);
    if (profile.role === 'cashier' && !normalizeGender(profile.cashier_gender)) {
      setOrders([]);
      setNotice('Akun kasir belum diberi jalur Putra atau Putri. Minta Super Admin mengatur cashier_gender pada profil akun ini.');
      setLoadingOrders(false);
      return;
    }
    // Pagination Supabase: ambil berurutan per 500 baris sampai halaman terakhir.
    // Bila pemuatan gagal di tengah jalan, data lama tetap dipertahankan agar tidak
    // menampilkan antrean parsial seolah-olah seluruh data sudah berhasil dimuat.
    const PAGE_SIZE = 500;
    const MAX_ROWS = 100000;
    let allRows = [];
    let fetchError = null;
    let reachedLimit = false;
    try {
      for (let from = 0; from < MAX_ROWS; from += PAGE_SIZE) {
        let query = supabase.from('orders')
          .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
          .order('created_at',{ascending:false})
          .order('id',{ascending:false})
          .range(from, from + PAGE_SIZE - 1);
        // Defense in depth: RLS tetap berlaku, ditambah batas jalur untuk kasir.
        if (profile.role === 'cashier') query = query.eq('guest_gender', normalizeGender(profile.cashier_gender));
        const {data,error} = await query;
        if (error) { fetchError = error; break; }
        const pageRows = data || [];
        allRows = allRows.concat(pageRows);
        if (pageRows.length < PAGE_SIZE) break;
        if (from + PAGE_SIZE >= MAX_ROWS) reachedLimit = true;
      }
    } catch (error) {
      fetchError = error;
    } finally {
      setLoadingOrders(false);
    }
    if (fetchError) {
      setNotice(`Gagal memuat pesanan: ${fetchError.message || 'Kesalahan jaringan.'}. Data antrean sebelumnya dipertahankan; tekan Muat ulang untuk mencoba lagi.`);
      return;
    }
    setOrders(allRows.map(mapOrder));
    if (reachedLimit) {
      setNotice(`Pemuatan mencapai batas aman ${MAX_ROWS.toLocaleString('id-ID')} pesanan. Gunakan rentang tanggal untuk menelusuri data lebih lama.`);
    }
  }
'@
if (!$content.Contains($old)) { throw 'Blok loadOrders berbeda dari versi yang diaudit. File tidak diubah. Ambil src/App.jsx terbaru dan audit ulang.' }
$backup = "$path.bak-sebelum-fix-pemuatan-pesanan"
if (!(Test-Path $backup)) { Copy-Item $path $backup }
$content = $content.Replace($old,$new)
[System.IO.File]::WriteAllText($path,$content,(New-Object System.Text.UTF8Encoding($false)))
$check = [System.IO.File]::ReadAllText($path,[System.Text.Encoding]::UTF8)
if (!$check.Contains('const MAX_ROWS = 100000;') -or !$check.Contains(".order('id',{ascending:false})") -or !$check.Contains('Data antrean sebelumnya dipertahankan')) {
  Copy-Item $backup $path -Force
  throw 'Validasi gagal; file awal dipulihkan dari backup.'
}
Write-Host 'Berhasil memperbarui src\App.jsx.' -ForegroundColor Green
Write-Host "Backup: $backup"
Write-Host 'Perubahan hanya pada pemuatan data pesanan.'

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appPath = Join-Path $root 'src\App.jsx'
$sqlPath = Join-Path $root 'supabase\migrations\202611210001_cancelled_orders_to_trash.sql'

if (!(Test-Path $appPath)) { throw 'src\App.jsx tidak ditemukan. Ekstrak ZIP ke root repository Warung Darul Ilmi.' }
if (!(Test-Path $sqlPath)) { throw 'File migrasi SQL tidak ditemukan di dalam paket.' }

$app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")

function Replace-Once {
  param([string]$Text,[string]$Old,[string]$New,[string]$Label)
  $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
  if ($first -lt 0) { throw "Bagian '$Label' tidak ditemukan. File mungkin bukan versi branch app yang diperiksa." }
  $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
  if ($second -ge 0) { throw "Bagian '$Label' ditemukan lebih dari sekali. Tidak ada file yang ditulis." }
  return $Text.Substring(0,$first) + $New + $Text.Substring($first + $Old.Length)
}

# Update only the status-update handler. Other order statuses keep their existing behavior.
$startMarker = '  async function updateOrder(id,patch) {'
$endMarker = '  async function softDeleteOrder(id) {'
$start = $app.IndexOf($startMarker, [System.StringComparison]::Ordinal)
$end = $app.IndexOf($endMarker, [System.StringComparison]::Ordinal)
if ($start -lt 0 -or $end -lt 0 -or $end -le $start) {
  throw 'Batas fungsi updateOrder tidak ditemukan. Tidak ada file yang ditulis.'
}

$newHandler = @'
  async function updateOrder(id,patch) {
    if (!supabase) return;
    const target = orders.find(o => o.id === id) || reportOrders.find(o => o.id === id) || distributionRows.find(o => o.id === id);
    if (!target) { setNotice('Pesanan tidak ditemukan pada antrean yang sedang dibuka. Muat ulang data.'); return; }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin untuk mengubah pesanan dari jalur lain.'); return;
    }

    try {
      // Cancellation is an atomic database action: status=cancelled and deleted_at set together.
      if (patch.status === 'cancelled') {
        const { error: cancelError } = await supabase.rpc('cancel_staff_order', { p_order_id: id });
        if (cancelError) throw cancelError;

        setNotice(`Pesanan ${target.number} dibatalkan dan dipindahkan ke Sampah. Pesanan dapat dipulihkan selama 3 hari.`);
        const refreshTasks = [loadOrders(), loadTrashOrders()];
        if (page === 'reports' && reportLoaded) refreshTasks.push(loadReportOrders());
        if (page === 'distribution') refreshTasks.push(loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo));
        await Promise.all(refreshTasks);
        return;
      }

      const {data:updatedOrder,error}=await supabase
        .from('orders')
        .update(patch)
        .eq('id',id)
        .select('id,status')
        .maybeSingle();

      if (error) {
        setNotice(`Perubahan gagal disimpan: ${error.message}`);
        return;
      }

      if (!updatedOrder || updatedOrder.id !== id) {
        setNotice('Perubahan tidak terkonfirmasi: baris pesanan tidak ditemukan atau tidak dapat diakses. Muat ulang antrean sebelum mencoba lagi.');
        await loadOrders();
        return;
      }

      if (patch.status !== undefined && updatedOrder.status !== patch.status) {
        setNotice(`Perubahan tidak terkonfirmasi: server mengembalikan status "${updatedOrder.status}" yang berbeda dari permintaan. Muat ulang antrean untuk memeriksa status terbaru.`);
        await loadOrders();
        return;
      }

      setNotice('Perubahan pesanan tersimpan dan telah diverifikasi dari database.');
      await loadOrders();
      if (page === 'reports' && reportLoaded) await loadReportOrders();
      if (page === 'distribution') await loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo);
    } catch (error) {
      setNotice(`Perubahan pesanan gagal dipastikan: ${error?.message || 'Kesalahan jaringan.'}. Muat ulang antrean untuk memeriksa status terbaru.`);
    }
  }
'@

$app = $app.Substring(0,$start) + $newHandler + "`n`n" + $app.Substring($end)

# Guard: ensure the report loader already excludes soft-deleted orders, and the cancellation RPC is used.
if (!$app.Contains(".is('deleted_at', null)")) {
  throw 'Filter deleted_at pada query laporan tidak ditemukan. Hentikan pemasangan agar laporan tidak menampilkan pesanan Sampah.'
}
if (!$app.Contains("supabase.rpc('cancel_staff_order', { p_order_id: id })")) {
  throw 'Pemanggilan RPC pembatalan tidak berhasil dipasang.'
}

# Backup and write only after every validation passed.
$backup = "$appPath.before-cancelled-to-trash"
Copy-Item $appPath $backup -Force
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($appPath, $app, $utf8NoBom)

Write-Host ''
Write-Host 'Perubahan kode pembatalan pesanan berhasil diterapkan.' -ForegroundColor Green
Write-Host "Backup: $backup"
Write-Host 'Jangan lupa menjalankan migrasi SQL di Supabase sebelum mencoba tombol Dibatalkan.'

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appPath = Join-Path $root 'src\App.jsx'
$migrationPath = Join-Path $root 'supabase\migrations\202611210001_cancel_order_to_trash.sql'

if (!(Test-Path $appPath)) { throw 'src\App.jsx tidak ditemukan. Ekstrak ZIP di root repository (folder package.json).' }
if (!(Test-Path $migrationPath)) { throw 'File migration SQL tidak ditemukan. Ekstrak seluruh ZIP ke root repository.' }

$app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8).Replace("`r`n","`n")

function Replace-Once {
  param([string]$Text,[string]$Old,[string]$New,[string]$Label)
  $p = $Text.IndexOf($Old,[System.StringComparison]::Ordinal)
  if ($p -lt 0) { throw "Bagian '$Label' tidak ditemukan. File mungkin berbeda dari versi branch app yang diperiksa." }
  if ($Text.IndexOf($Old,$p+$Old.Length,[System.StringComparison]::Ordinal) -ge 0) {
    throw "Bagian '$Label' ditemukan lebih dari sekali. Tidak ada file yang ditulis."
  }
  return $Text.Substring(0,$p)+$New+$Text.Substring($p+$Old.Length)
}

# Saat status diubah menjadi cancelled, panggil satu RPC atomik:
# update status + deleted_at + deleted_by bersamaan di database.
$old = @'
  async function updateOrder(id,patch) {
    if (!supabase) return;
    const target = orders.find(o => o.id === id) || reportOrders.find(o => o.id === id) || distributionRows.find(o => o.id === id);
    if (!target) { setNotice('Pesanan tidak ditemukan pada antrean yang sedang dibuka. Muat ulang data.'); return; }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin untuk mengubah pesanan dari jalur lain.'); return;
    }

    try {
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
$new = @'
  async function updateOrder(id,patch) {
    if (!supabase) return;
    const target = orders.find(o => o.id === id) || reportOrders.find(o => o.id === id) || distributionRows.find(o => o.id === id);
    if (!target) { setNotice('Pesanan tidak ditemukan pada antrean yang sedang dibuka. Muat ulang data.'); return; }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin untuk mengubah pesanan dari jalur lain.'); return;
    }

    try {
      let updatedOrder = null;
      if (patch.status === 'cancelled') {
        // Batalkan dan pindahkan ke Sampah dalam satu operasi database yang atomik.
        const { data, error } = await supabase.rpc('cancel_staff_order', { p_order_id: id });
        if (error) throw error;
        updatedOrder = { id, status: 'cancelled', deleted_at: data };
      } else {
        const {data,error}=await supabase
          .from('orders')
          .update(patch)
          .eq('id',id)
          .select('id,status')
          .maybeSingle();

        if (error) throw error;
        updatedOrder = data;
      }

      if (!updatedOrder || updatedOrder.id !== id) {
        setNotice('Perubahan tidak terkonfirmasi: baris pesanan tidak ditemukan atau tidak dapat diakses. Muat ulang antrean sebelum mencoba lagi.');
        await Promise.all([loadOrders(), page === 'reports' && reportLoaded ? loadReportOrders() : Promise.resolve()]);
        return;
      }

      if (patch.status !== undefined && updatedOrder.status !== patch.status) {
        setNotice(`Perubahan tidak terkonfirmasi: server mengembalikan status "${updatedOrder.status}" yang berbeda dari permintaan. Muat ulang antrean untuk memeriksa status terbaru.`);
        await Promise.all([loadOrders(), page === 'reports' && reportLoaded ? loadReportOrders() : Promise.resolve()]);
        return;
      }

      if (patch.status === 'cancelled') {
        setNotice(`Pesanan ${target.number} dibatalkan dan dipindahkan ke Sampah. Pesanan dapat dipulihkan selama 3 hari.`);
        const refreshTasks = [loadOrders(), loadTrashOrders()];
        if (page === 'reports' && reportLoaded) refreshTasks.push(loadReportOrders());
        if (page === 'distribution') refreshTasks.push(loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo));
        await Promise.all(refreshTasks);
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
$app = Replace-Once $app $old $new 'fungsi updateOrder'

# Validasi agar pembatalan tidak lagi menggunakan update langsung.
if (!$app.Contains("supabase.rpc('cancel_staff_order'")) { throw 'Validasi gagal: RPC pembatalan tidak ditemukan.' }
if (!$app.Contains("Pesanan ${target.number} dibatalkan dan dipindahkan ke Sampah.")) { throw 'Validasi pesan pemindahan ke Sampah gagal.' }

$backup = "$appPath.before-cancel-to-trash"
Copy-Item $appPath $backup -Force
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($appPath,$app,$utf8NoBom)

Write-Host ''
Write-Host 'Perbaikan pembatalan ke Sampah berhasil diterapkan.' -ForegroundColor Green
Write-Host "Backup dibuat: $backup"
Write-Host 'Jalankan migration SQL baru di Supabase sebelum menguji pembatalan.'

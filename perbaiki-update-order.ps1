$ErrorActionPreference = 'Stop'

$projectRoot = (Get-Location).Path
$appPath = Join-Path $projectRoot 'src\App.jsx'

if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) {
    throw "File tidak ditemukan: $appPath`nJalankan skrip dari folder utama proyek Warung Darul Ilmi."
}

$source = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)
$lineEnding = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
$normalized = $source.Replace("`r`n", "`n")

# Pastikan perbaikan checkout WhatsApp dan validasi RPC sebelumnya tetap ada.
$requiredMarkers = @(
    'orderSubmitting',
    'whatsAppFallbackUrl',
    'whatsappTab.location.replace(whatsappUrl)',
    'responseRows.length !== 1',
    'orderIdValid'
)
foreach ($marker in $requiredMarkers) {
    if (-not $normalized.Contains($marker)) {
        throw "Pemeriksaan keamanan gagal: penanda '$marker' tidak ditemukan. File tidak diubah agar perbaikan sebelumnya tidak tertimpa."
    }
}

$oldBlock = @'
  async function updateOrder(id,patch) {
    if (!supabase) return;
    const target = orders.find(o => o.id === id);
    if (!target) { setNotice('Pesanan tidak ditemukan pada antrean yang sedang dibuka. Muat ulang data.'); return; }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin untuk mengubah pesanan dari jalur lain.'); return;
    }
    if (patch.status === 'delivered' && target.status !== 'ready') {
      setNotice('Pesanan hanya dapat ditandai diserahkan setelah berstatus Siap diserahkan.'); return;
    }
    const {error}=await supabase.from('orders').update(patch).eq('id',id);
    if (error) setNotice(`Perubahan gagal disimpan: ${error.message}`); else { setNotice('Perubahan pesanan tersimpan.'); await loadOrders(); }
  }
'@

$newBlock = @'
  async function updateOrder(id,patch) {
    if (!supabase) return;
    const target = orders.find(o => o.id === id);
    if (!target) { setNotice('Pesanan tidak ditemukan pada antrean yang sedang dibuka. Muat ulang data.'); return; }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin untuk mengubah pesanan dari jalur lain.'); return;
    }
    if (patch.status === 'delivered' && target.status !== 'ready') {
      setNotice('Pesanan hanya dapat ditandai diserahkan setelah berstatus Siap diserahkan.'); return;
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
    } catch (error) {
      setNotice(`Perubahan pesanan gagal dipastikan: ${error?.message || 'Kesalahan jaringan.'}. Muat ulang antrean untuk memeriksa status terbaru.`);
    }
  }
'@

$oldCount = ([regex]::Matches($normalized, [regex]::Escape($oldBlock))).Count
if ($oldCount -eq 0) {
    if ($normalized.Contains(".select('id,status')") -and $normalized.Contains('.maybeSingle()') -and $normalized.Contains('Perubahan pesanan tersimpan dan telah diverifikasi dari database.')) {
        Write-Host 'Perbaikan updateOrder tampaknya sudah terpasang. Tidak ada perubahan.' -ForegroundColor Yellow
        exit 0
    }
    throw 'Blok updateOrder versi yang diharapkan tidak ditemukan. File tidak diubah; kemungkinan kode lokal sudah berbeda dari branch app yang diperiksa.'
}
if ($oldCount -ne 1) {
    throw "Ditemukan $oldCount blok updateOrder yang cocok. File tidak diubah karena hasilnya tidak aman."
}

$updated = $normalized.Replace($oldBlock, $newBlock)
if ($lineEnding -eq "`r`n") { $updated = $updated.Replace("`n", "`r`n") }

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = Join-Path (Split-Path $appPath -Parent) "App.jsx.bak-update-order-$timestamp"
Copy-Item -LiteralPath $appPath -Destination $backupPath

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
try {
    [System.IO.File]::WriteAllText($appPath, $updated, $utf8NoBom)
    $written = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)
    $checks = @(
        ".select('id,status')",
        '.maybeSingle()',
        'if (!updatedOrder || updatedOrder.id !== id)',
        'updatedOrder.status !== patch.status',
        'Perubahan pesanan tersimpan dan telah diverifikasi dari database.'
    )
    foreach ($check in $checks) {
        if (-not $written.Contains($check)) { throw "Verifikasi setelah penulisan gagal: '$check' tidak ditemukan." }
    }
} catch {
    Copy-Item -LiteralPath $backupPath -Destination $appPath -Force
    throw "Perubahan gagal diverifikasi. File asli sudah dipulihkan dari backup. Detail: $($_.Exception.Message)"
}

Write-Host ''
Write-Host 'Berhasil: src\App.jsx telah diperbarui.' -ForegroundColor Green
Write-Host "Backup file lama: $backupPath"
Write-Host 'Perubahan hanya menyentuh fungsi updateOrder() dalam src\App.jsx.'

$ErrorActionPreference = 'Stop'

$appPath = Join-Path (Get-Location) 'src\App.jsx'
if (-not (Test-Path -LiteralPath $appPath)) { throw 'src\App.jsx tidak ditemukan. Jalankan dari folder utama proyek.' }
if (-not (Test-Path -LiteralPath (Join-Path (Get-Location) 'package.json'))) { throw 'package.json tidak ditemukan. Jalankan dari folder utama proyek.' }

$app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)

function Replace-ExactlyOnce {
  param([string]$Source, [string]$OldText, [string]$NewText, [string]$Label)
  $count = [System.Text.RegularExpressions.Regex]::Matches($Source, [System.Text.RegularExpressions.Regex]::Escape($OldText)).Count
  if ($count -ne 1) { throw "Patch dibatalkan: '$Label' ditemukan $count kali (seharusnya tepat 1). File tidak ditimpa. Pastikan file sesuai dengan branch app yang diaudit atau hentikan dan audit ulang." }
  return $Source.Replace($OldText, $NewText)
}

# Branch saat ini sudah memiliki Realtime + queued refresh + refresh saat kembali.
# Perkuat dua hal tanpa menambah ref/hook yang sudah ada:
# - setelah query selesai, refresh antrean dilakukan setelah render state loading=false;
# - perubahan Realtime ketika filter tanggal belum ditentukan tidak dianggap sebagai query yang bisa dijalankan.
$oldFinally = @'
    } finally {
      reportLoadInFlightRef.current = false;
      setReportLoading(false);

      if (reportRefreshQueuedRef.current && page === 'reports' && isAdmin) {
        reportRefreshQueuedRef.current = false;
        loadReportOrders();
      }
    }
'@
$newFinally = @'
    } finally {
      reportLoadInFlightRef.current = false;
      setReportLoading(false);

      // Defer a queued refresh until the current render has cleared the loading state.
      if (reportRefreshQueuedRef.current && page === 'reports' && isAdmin && (reportFrom || reportTo)) {
        reportRefreshQueuedRef.current = false;
        Promise.resolve().then(() => loadReportOrders());
      }
    }
'@
$app = Replace-ExactlyOnce $app $oldFinally $newFinally 'penyelesaian antrian refresh laporan'

# Keep the filters as they are; strengthen the distinction in explanatory copy.
$oldCashier = 'Filter tanggal Kasir menggunakan tanggal pesanan dibuat (created_at), bukan tanggal pengiriman.'
$newCashier = 'Filter tanggal Kasir menggunakan tanggal pesanan dibuat (created_at). Ini bukan tanggal pengiriman.'
$app = Replace-ExactlyOnce $app $oldCashier $newCashier 'keterangan filter tanggal Kasir'

$oldReport = 'Rentang tanggal Laporan menggunakan tanggal pengiriman (delivery_date). Karena Kasir menggunakan tanggal pesanan dibuat (created_at), transaksi yang sama dapat masuk pada tanggal yang berbeda di kedua halaman.'
$newReport = 'Rentang tanggal Laporan menggunakan tanggal pengiriman (delivery_date), sedangkan Kasir menggunakan tanggal pesanan dibuat (created_at). Untuk membandingkan transaksi yang sama, gunakan nomor pesanan; rentang tanggal kedua halaman tidak harus menghasilkan daftar yang identik.'
$app = Replace-ExactlyOnce $app $oldReport $newReport 'keterangan filter tanggal Laporan'

# Prevent accidental patching against another implementation state.
$required = @(
  'const reportRefreshQueuedRef = useRef(false);',
  'const reportLoadedRef = useRef(false);',
  'if (isAdmin && (reportLoadedRef.current || reportLoadInFlightRef.current))',
  'if (page !== ''reports'' || !isAdmin) return;',
  'Promise.resolve().then(() => loadReportOrders());',
  'Ini bukan tanggal pengiriman.',
  'Untuk membandingkan transaksi yang sama, gunakan nomor pesanan;'
)
foreach ($marker in $required) { if (-not $app.Contains($marker)) { throw "Pemeriksaan akhir gagal: '$marker' tidak ditemukan. File asli tidak diubah." } }

$backupPath = "$appPath.before-kasir-laporan-sync"
if (Test-Path -LiteralPath $backupPath) { $backupPath = "$appPath.before-kasir-laporan-sync-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
Copy-Item -LiteralPath $appPath -Destination $backupPath
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($appPath, $app, $utf8NoBom)
Write-Host 'Patch integrasi Kasir-Laporan berhasil diterapkan.' -ForegroundColor Green
Write-Host "Backup: $backupPath"
Write-Host 'Hanya src/App.jsx yang diubah. Tidak ada SQL atau data Supabase yang diubah.'

$ErrorActionPreference = 'Stop'

$appPath = Join-Path (Get-Location) 'src\App.jsx'
if (-not (Test-Path -LiteralPath $appPath)) {
    throw 'src\App.jsx tidak ditemukan. Ekstrak ZIP di folder utama proyek yang berisi package.json.'
}
if (-not (Test-Path -LiteralPath (Join-Path (Get-Location) 'package.json'))) {
    throw 'package.json tidak ditemukan. Jalankan skrip dari folder utama proyek Warung Darul Ilmi.'
}

$app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)

function Replace-ExactlyOnce {
    param(
        [string]$Source,
        [string]$OldText,
        [string]$NewText,
        [string]$Label
    )

    $escapedOldText = [System.Text.RegularExpressions.Regex]::Escape($OldText)
    $matchCount = [System.Text.RegularExpressions.Regex]::Matches($Source, $escapedOldText).Count
    if ($matchCount -ne 1) {
        throw "Patch dibatalkan: penanda '$Label' ditemukan $matchCount kali (seharusnya tepat 1). File tidak akan ditimpa. Pastikan src/App.jsx berasal dari branch app yang diaudit."
    }
    return $Source.Replace($OldText, $NewText)
}

# 1. Simpan status laporan terbaru dalam ref agar dapat dibaca callback Realtime.
$oldRefs = @'
  const distributionLoadVersionRef = useRef(0);
  const reportLoadInFlightRef = useRef(false);
  const cashierOrderRangeRef = useRef({ from: '', to: '', enabled: false });
'@
$newRefs = @'
  const distributionLoadVersionRef = useRef(0);
  const reportLoadInFlightRef = useRef(false);
  const reportRefreshQueuedRef = useRef(false);
  const reportLoadedRef = useRef(false);
  reportLoadedRef.current = reportLoaded;
  const cashierOrderRangeRef = useRef({ from: '', to: '', enabled: false });
'@
$app = Replace-ExactlyOnce $app $oldRefs $newRefs 'ref sinkronisasi laporan'

# 2. Perubahan tabel orders mengantrekan atau menjalankan refresh laporan.
$oldRealtime = @'
        if (ordersLoadInFlightRef.current) ordersRefreshQueuedRef.current = true;
        else loadOrders();
        setOrdersRealtimeVersion(version => version + 1);
'@
$newRealtime = @'
        if (ordersLoadInFlightRef.current) ordersRefreshQueuedRef.current = true;
        else loadOrders();

        // Keep the report in sync with order changes received through Supabase Realtime.
        // While the cashier page is open, remember that a previously loaded report is stale.
        if (isAdmin && (reportLoadedRef.current || reportLoadInFlightRef.current)) {
          if (page === 'reports') loadReportOrders();
          else reportRefreshQueuedRef.current = true;
        }

        setOrdersRealtimeVersion(version => version + 1);
'@
$app = Replace-ExactlyOnce $app $oldRealtime $newRealtime 'callback Realtime pesanan'

# 3. Jangan mengabaikan refresh kedua jika query laporan sebelumnya masih berjalan.
$oldReportGuard = @'
  async function loadReportOrders() {
    if (!supabase || !isAdmin || reportLoadInFlightRef.current) return;
'@
$newReportGuard = @'
  async function loadReportOrders() {
    if (!supabase || !isAdmin) return;
    if (reportLoadInFlightRef.current) {
      reportRefreshQueuedRef.current = true;
      return;
    }
'@
$app = Replace-ExactlyOnce $app $oldReportGuard $newReportGuard 'pengaman pemuatan laporan'

# 4. Setelah pemuatan selesai, jalankan satu refresh susulan bila ada perubahan saat query berlangsung.
$oldReportFinally = @'
    } finally {
      reportLoadInFlightRef.current = false;
      setReportLoading(false);
    }
  }  async function loadCashierAccounts() {
'@
$newReportFinally = @'
    } finally {
      reportLoadInFlightRef.current = false;
      setReportLoading(false);

      if (reportRefreshQueuedRef.current && page === 'reports' && isAdmin) {
        reportRefreshQueuedRef.current = false;
        loadReportOrders();
      }
    }
  }

  // Returning to Reports refreshes the previously loaded result, even if Realtime
  // was unavailable while the user was working on the Cashier page.
  useEffect(() => {
    if (page !== 'reports' || !isAdmin) return;
    if (reportRefreshQueuedRef.current || reportLoadedRef.current) {
      reportRefreshQueuedRef.current = false;
      loadReportOrders();
    }
  }, [page, isAdmin]);

  async function loadCashierAccounts() {
'@
$app = Replace-ExactlyOnce $app $oldReportFinally $newReportFinally 'akhir pemuatan dan efek navigasi laporan'

# 5. Jelaskan secara eksplisit bahwa tanggal Kasir berarti created_at.
$oldCashierIntro = @'
</p>{profile?.role==='cashier'&&!['Putra','Putri'].includes(profile.cashier_gender)&&<div className="notice">Akun kasir belum memiliki jalur Putra/Putri. Super Admin harus mengatur kolom cashier_gender pada profil akun.</div>}
'@
$newCashierIntro = @'
</p><p className="fine-print">Filter tanggal Kasir menggunakan tanggal pesanan dibuat (created_at), bukan tanggal pengiriman.</p>{profile?.role==='cashier'&&!['Putra','Putri'].includes(profile.cashier_gender)&&<div className="notice">Akun kasir belum memiliki jalur Putra/Putri. Super Admin harus mengatur kolom cashier_gender pada profil akun.</div>}
'@
$app = Replace-ExactlyOnce $app $oldCashierIntro $newCashierIntro 'keterangan dasar tanggal Kasir'

# 6. Jelaskan secara eksplisit bahwa Laporan berarti delivery_date dan hasil tanggalnya
#    memang dapat berbeda dari halaman Kasir. Query filter tetap tidak diubah.
$oldReportIntro = @'
<p className="muted">Filter berdasarkan tanggal pengiriman dan kategori santri. Excel, PDF ceklis distribusi, dan TXT rekap menu mengikuti filter yang dipilih.</p></div><div className="stats">
'@
$newReportIntro = @'
<p className="muted">Filter berdasarkan tanggal pengiriman dan kategori santri. Excel, PDF ceklis distribusi, dan TXT rekap menu mengikuti filter yang dipilih.</p><p className="fine-print">Rentang tanggal Laporan menggunakan tanggal pengiriman (delivery_date). Karena Kasir menggunakan tanggal pesanan dibuat (created_at), transaksi yang sama dapat masuk pada tanggal yang berbeda di kedua halaman.</p></div><div className="stats">
'@
$app = Replace-ExactlyOnce $app $oldReportIntro $newReportIntro 'keterangan dasar tanggal Laporan'

# Final guard: ensure the new synchronization code exists before writing.
$requiredMarkers = @(
    'const reportRefreshQueuedRef = useRef(false);',
    'const reportLoadedRef = useRef(false);',
    'if (page !== ''reports'' || !isAdmin) return;',
    'Filter tanggal Kasir menggunakan tanggal pesanan dibuat (created_at)',
    'Rentang tanggal Laporan menggunakan tanggal pengiriman (delivery_date)'
)
foreach ($marker in $requiredMarkers) {
    if (-not $app.Contains($marker)) {
        throw "Patch dibatalkan: pemeriksaan akhir gagal untuk penanda '$marker'. File asli tetap aman."
    }
}

$backupPath = "$appPath.before-kasir-laporan-sync"
if (Test-Path -LiteralPath $backupPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$appPath.before-kasir-laporan-sync-$stamp"
}
Copy-Item -LiteralPath $appPath -Destination $backupPath
$utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
[System.IO.File]::WriteAllText($appPath, $app, $utf8NoBom)

Write-Host ''
Write-Host 'Patch sinkronisasi Kasir-Laporan berhasil diterapkan.' -ForegroundColor Green
Write-Host "File diperbarui : $appPath"
Write-Host "Backup dibuat   : $backupPath"
Write-Host 'Tidak ada file SQL, konfigurasi Supabase, atau data database yang diubah.'

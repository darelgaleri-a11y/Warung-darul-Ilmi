$ErrorActionPreference = 'Stop'

$repoRoot = (Get-Location).Path
$appPath = Join-Path $repoRoot 'src\App.jsx'
if (-not (Test-Path $appPath)) {
    throw "File src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek yang berisi package.json."
}
if (-not (Test-Path (Join-Path $repoRoot 'package.json'))) {
    throw "package.json tidak ditemukan. Jalankan skrip dari folder utama proyek."
}

$branch = (& git -C $repoRoot branch --show-current 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne 'app') {
    throw "Patch aman hanya untuk branch 'app'. Branch aktif saat ini: '$branch'. Pindah ke branch app dan tarik pembaruan terlebih dahulu."
}

# Git blob SHA for src/App.jsx fetched directly from the audited GitHub branch app.
$expectedBlobSha = '2c61059ebb1ae0a14e9204ffa0def4d2b7074e05'
$headBlobOutput = & git -C $repoRoot rev-parse 'HEAD:src/App.jsx' 2>$null
$headBlobSha = ($headBlobOutput | Out-String).Trim()
$worktreeDiff = & git -C $repoRoot diff --quiet -- src/App.jsx 2>$null
$worktreeChanged = ($LASTEXITCODE -ne 0)
$stagedDiff = & git -C $repoRoot diff --cached --quiet -- src/App.jsx 2>$null
$stagedChanged = ($LASTEXITCODE -ne 0)
if ($headBlobSha -ne $expectedBlobSha -or $worktreeChanged -or $stagedChanged) {
    throw "Patch dibatalkan: src/App.jsx harus sama persis dengan versi branch app yang diaudit dan tidak memiliki perubahan lokal. SHA pada HEAD: '$headBlobSha'; SHA yang diharapkan: '$expectedBlobSha'. Tarik branch app terbaru dan simpan perubahan lokal terlebih dahulu. File tidak diubah."
}

function Replace-Once {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$OldText,
        [Parameter(Mandatory=$true)][string]$NewText,
        [Parameter(Mandatory=$true)][string]$Label
    )
    $OldText = $OldText.Replace("`r`n", "`n").TrimEnd([char]10, [char]13)
    $NewText = $NewText.Replace("`r`n", "`n").TrimEnd([char]10, [char]13)
    $count = 0
    $searchFrom = 0
    while ($true) {
        $foundAt = $Source.IndexOf($OldText, $searchFrom, [System.StringComparison]::Ordinal)
        if ($foundAt -lt 0) { break }
        $count++
        $searchFrom = $foundAt + $OldText.Length
    }
    if ($count -ne 1) {
        throw "Patch dibatalkan: bagian '$Label' ditemukan $count kali (seharusnya tepat 1). File tidak diubah."
    }
    return $Source.Replace($OldText, $NewText)
}

$original = [System.IO.File]::ReadAllText($appPath)
$newLine = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
$app = $original.Replace("`r`n", "`n")

$old = @'
  const [reportGender, setReportGender] = useState('Semua');
'@
$new = @'
  const [reportGender, setReportGender] = useState('Semua');
  const [reportDateBasis, setReportDateBasis] = useState('created_at');
'@
$app = Replace-Once $app $old $new 'state dasar tanggal laporan'

$old = @'
  const reportLoadInFlightRef = useRef(false);
  const reportRefreshQueuedRef = useRef(false);
  const reportLoadedRef = useRef(false);
'@
$new = @'
  const reportLoadInFlightRef = useRef(false);
  const reportRefreshQueuedRef = useRef(false);
  const reportLoadedRef = useRef(false);
  const activePageRef = useRef(page);
  activePageRef.current = page;
'@
$app = Replace-Once $app $old $new 'referensi halaman aktif'

$old = @'
        // Keep the report in sync with order changes received through Supabase Realtime.
        // While the cashier page is open, remember that a previously loaded report is stale.
        if (isAdmin && (reportLoadedRef.current || reportLoadInFlightRef.current)) {
          if (page === 'reports') loadReportOrders();
          else reportRefreshQueuedRef.current = true;
        }
'@
$new = @'
        // Mark an already loaded/in-progress report as stale. The versioned effect below
        // refreshes it while Reports is open, or when the user returns from another page.
        if (isAdmin && (reportLoadedRef.current || reportLoadInFlightRef.current)) {
          reportRefreshQueuedRef.current = true;
        }
'@
$app = Replace-Once $app $old $new 'penanda perubahan laporan dari realtime'

$old = @'
  useEffect(() => {
    if (page !== 'reports' || !isAdmin) return;
    if (reportRefreshQueuedRef.current || reportLoadedRef.current) {
      reportRefreshQueuedRef.current = false;
      loadReportOrders();
    }
  }, [page, isAdmin]);
'@
$new = @'
  useEffect(() => {
    if (page !== 'reports' || !isAdmin) return;
    if (reportRefreshQueuedRef.current || reportLoadedRef.current || reportLoadInFlightRef.current) {
      reportRefreshQueuedRef.current = false;
      loadReportOrders();
    }
  }, [page, isAdmin, ordersRealtimeVersion]);
'@
$app = Replace-Once $app $old $new 'efek sinkronisasi laporan kasir-realtime'

$old = @'
      if (reportRefreshQueuedRef.current && page === 'reports' && isAdmin && (reportFrom || reportTo)) {
'@
$new = @'
      if (reportRefreshQueuedRef.current && activePageRef.current === 'reports' && isAdmin && (reportFrom || reportTo)) {
'@
$app = Replace-Once $app $old $new 'pemeriksaan halaman saat refresh tertunda'

$old = @'
    if (!reportFrom && !reportTo) {
      setReportLoaded(false);
      setNotice('Pilih minimal satu batas tanggal pengiriman agar laporan mengambil data sesuai periode, bukan seluruh riwayat sekaligus.');
      return;
    }
'@
$new = @'
    if (!reportFrom && !reportTo) {
      setReportLoaded(false);
      setNotice(`Pilih minimal satu batas tanggal ${reportDateBasis === 'created_at' ? 'pemesanan dibuat' : 'pengiriman'} agar laporan mengambil data sesuai periode, bukan seluruh riwayat sekaligus.`);
      return;
    }
'@
$app = Replace-Once $app $old $new 'pesan validasi rentang laporan'

$old = @'
        if (reportFrom) query = query.gte('delivery_date', reportFrom);
        if (reportTo) query = query.lte('delivery_date', reportTo);
'@
$new = @'
        if (reportDateBasis === 'created_at') {
          if (reportFrom) query = query.gte('created_at', localDateStartIso(reportFrom));
          if (reportTo) query = query.lt('created_at', localDateStartIso(reportTo, 1));
        } else {
          if (reportFrom) query = query.gte('delivery_date', reportFrom);
          if (reportTo) query = query.lte('delivery_date', reportTo);
        }
'@
$app = Replace-Once $app $old $new 'query tanggal laporan'

$old = @'
  function reportPeriodLabel() {
    const formatDate = value => value ? new Intl.DateTimeFormat('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(`${value}T00:00:00`)) : '';
    if (reportFrom && reportTo && reportFrom !== reportTo) return `${formatDate(reportFrom)} s.d. ${formatDate(reportTo)}`;
    return formatDate(reportFrom || reportTo) || 'Periode laporan';
  }
'@
$new = @'
  function reportPeriodLabel() {
    const formatDate = value => value ? new Intl.DateTimeFormat('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(`${value}T00:00:00`)) : '';
    const basisLabel = reportDateBasis === 'created_at' ? 'Tanggal pesanan dibuat' : 'Tanggal pengiriman';
    if (reportFrom && reportTo && reportFrom !== reportTo) return `${basisLabel}: ${formatDate(reportFrom)} s.d. ${formatDate(reportTo)}`;
    return `${basisLabel}: ${formatDate(reportFrom || reportTo) || 'Periode laporan'}`;
  }
'@
$app = Replace-Once $app $old $new 'label periode ekspor laporan'

$old = @'
      const fileName = `laporan-warung-darul-ilmi-${reportFrom || 'awal'}-${reportTo || 'terkini'}.xlsx`;
'@
$new = @'
      const fileName = `laporan-warung-darul-ilmi-${reportDateBasis}-${reportFrom || 'awal'}-${reportTo || 'terkini'}.xlsx`;
'@
$app = Replace-Once $app $old $new 'nama file Excel berdasarkan tipe tanggal'

$old = @'
Filter berdasarkan tanggal pengiriman dan kategori santri. Excel, PDF ceklis distribusi, dan TXT rekap menu mengikuti filter yang dipilih.
'@
$new = @'
Filter berdasarkan tanggal pesanan dibuat (agar dapat dibandingkan langsung dengan Kasir) atau tanggal pengiriman. Excel, PDF ceklis distribusi, dan TXT rekap menu mengikuti dasar tanggal serta filter yang dipilih.
'@
$app = Replace-Once $app $old $new 'deskripsi halaman laporan'

$old = @'
Rentang tanggal Laporan menggunakan tanggal pengiriman (delivery_date), sedangkan Kasir menggunakan tanggal pesanan dibuat (created_at). Untuk membandingkan transaksi yang sama, gunakan nomor pesanan; rentang tanggal kedua halaman tidak harus menghasilkan daftar yang identik.
'@
$new = @'
Gunakan "Tanggal pesanan dibuat" untuk membandingkan transaksi berdasarkan filter Kasir. Pilih "Tanggal pengiriman" untuk menyiapkan kebutuhan distribusi.
'@
$app = Replace-Once $app $old $new 'penjelasan perbedaan dasar tanggal'

$old = @'
<label>Dari tanggal pengiriman<input type="date" value={reportFrom}
'@
$new = @'
<label>Dasar tanggal<select value={reportDateBasis} disabled={reportLoading} onChange={e=>{setReportDateBasis(e.target.value);setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}}><option value="created_at">Tanggal pesanan dibuat (samakan dengan Kasir)</option><option value="delivery_date">Tanggal pengiriman</option></select></label><label>{reportDateBasis === 'created_at' ? 'Dari tanggal pemesanan' : 'Dari tanggal pengiriman'}<input type="date" value={reportFrom}
'@
$app = Replace-Once $app $old $new 'pilihan dasar tanggal laporan'

$old = @'
<label>Sampai tanggal pengiriman<input type="date" value={reportTo}
'@
$new = @'
<label>{reportDateBasis === 'created_at' ? 'Sampai tanggal pemesanan' : 'Sampai tanggal pengiriman'}<input type="date" value={reportTo}
'@
$app = Replace-Once $app $old $new 'label tanggal akhir laporan'

$old = @'
onClick={()=>{setReportFrom('');setReportTo('');setReportGender('Semua');setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}} disabled={reportLoading}
'@
$new = @'
onClick={()=>{setReportFrom('');setReportTo('');setReportGender('Semua');setReportDateBasis('created_at');setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}} disabled={reportLoading}
'@
$app = Replace-Once $app $old $new 'reset filter laporan'

$old = @'
<span className="muted">{reportFrom||'Awal'} s.d. {reportTo||'Terbaru'}  |  {reportGender==='Semua'?'Putra & Putri':reportGender}</span>
'@
$new = @'
<span className="muted">{reportDateBasis === 'created_at' ? 'Tanggal dibuat' : 'Tanggal pengiriman'}: {reportFrom||'Awal'} s.d. {reportTo||'Terbaru'}  |  {reportGender==='Semua'?'Putra & Putri':reportGender}</span>
'@
$app = Replace-Once $app $old $new 'ringkasan filter laporan'

$old = @'
Pilih rentang tanggal pengiriman, lihat transaksi yang masuk dalam periode tersebut, lalu unduh laporan Excel dengan satu baris untuk setiap transaksi santri.
'@
$new = @'
Pilih dasar tanggal dan rentangnya, lihat transaksi pada periode tersebut, lalu unduh laporan Excel dengan satu baris untuk setiap transaksi santri.
'@
$app = Replace-Once $app $old $new 'deskripsi laporan di portal admin'

# Only after every target has been found exactly once is the original file backed up and replaced.
$backupPath = "$appPath.before-kasir-laporan-sync-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $appPath -Destination $backupPath
if ($newLine -eq "`r`n") { $app = $app.Replace("`n", "`r`n") }
[System.IO.File]::WriteAllText($appPath, $app, [System.Text.UTF8Encoding]::new($false))

Write-Host 'Patch Kasir-Laporan berhasil diterapkan.' -ForegroundColor Green
Write-Host "Cadangan: $backupPath"
Write-Host 'Perubahan: sinkronisasi laporan melalui Realtime + refresh saat kembali ke Laporan; pilihan tanggal dibuat/pengiriman.'

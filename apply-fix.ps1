$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appPath = Join-Path $root 'src\App.jsx'

if (!(Test-Path $appPath)) {
  throw 'src\App.jsx tidak ditemukan. Ekstrak ZIP di folder utama repository Warung Darul Ilmi (folder yang memiliki package.json).'
}

$app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")

function Replace-Once {
  param([string]$Text, [string]$Old, [string]$New, [string]$Label)
  $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
  if ($first -lt 0) { throw "Bagian '$Label' tidak ditemukan. File mungkin tidak cocok dengan branch app yang diperiksa." }
  $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
  if ($second -ge 0) { throw "Bagian '$Label' ditemukan lebih dari sekali. Tidak ada file yang ditulis." }
  return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

# Perbaikan A: fungsi hapus dapat mencari pesanan dari semua layar yang memakai OrderList.
$oldDelete = @'
  async function softDeleteOrder(id) {
    if (!supabase || !isStaff) return;
    const target = orders.find(order => order.id === id);
    if (!target) { setNotice('Pesanan tidak ditemukan pada antrean aktif. Muat ulang antrean.'); return; }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin menghapus pesanan dari jalur lain.');
      return;
    }
    try {
      const { error } = await supabase.rpc('soft_delete_staff_order', { p_order_id: id });
      if (error) throw error;
      setNotice(`Pesanan ${target.number} dipindahkan ke Sampah. Pesanan dapat dipulihkan selama 3 hari.`);
      await Promise.all([loadOrders(), loadTrashOrders()]);
    } catch (error) {
      setNotice(`Pesanan gagal dipindahkan ke Sampah: ${error?.message || 'Kesalahan jaringan.'}`);
    }
  }

'@
$newDelete = @'
  async function softDeleteOrder(id) {
    if (!supabase || !isStaff) return;
    // Pesanan bisa berasal dari antrean Kasir, Laporan, atau Distribusi.
    const target = [orders, reportOrders, distributionRows]
      .flat()
      .find(order => order.id === id);
    if (!target) {
      setNotice('Pesanan tidak ditemukan pada daftar aktif. Muat ulang data lalu coba kembali.');
      return;
    }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin menghapus pesanan dari jalur lain.');
      return;
    }
    try {
      const { error } = await supabase.rpc('soft_delete_staff_order', { p_order_id: id });
      if (error) throw error;
      setNotice(`Pesanan ${target.number} dipindahkan ke Sampah. Pesanan dapat dipulihkan selama 3 hari.`);
      const refreshTasks = [loadOrders(), loadTrashOrders()];
      if (page === 'reports' && reportLoaded) refreshTasks.push(loadReportOrders());
      if (page === 'distribution') refreshTasks.push(loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo));
      await Promise.all(refreshTasks);
    } catch (error) {
      setNotice(`Pesanan gagal dipindahkan ke Sampah: ${error?.message || 'Kesalahan jaringan.'}`);
    }
  }

'@
$app = Replace-Once $app $oldDelete $newDelete 'handler soft delete'

# Perbaikan B: sambungkan aksi hapus pada OrderList di halaman Laporan.
$oldReport = '<OrderList orders={reportOrders} onStatus={(id,v)=>updateOrder(id,{status:v})} onEdit={openOrderEditor}/>'
$newReport = '<OrderList orders={reportOrders} onStatus={(id,v)=>updateOrder(id,{status:v})} onEdit={openOrderEditor} onDelete={softDeleteOrder}/>'
$app = Replace-Once $app $oldReport $newReport 'OrderList halaman Laporan'

# Perbaikan C: jadikan halaman preview mandiri dengan tombol cetak manual.
# Ini menghindari window.print() otomatis ketika tab baru masih sedang dimuat di Android.
$startMarker = '  function exportPdfChecklist() {'
$endMarker = '  async function exportTxtSummary() {'
$start = $app.IndexOf($startMarker, [System.StringComparison]::Ordinal)
$end = $app.IndexOf($endMarker, [System.StringComparison]::Ordinal)
if ($start -lt 0 -or $end -lt 0 -or $end -le $start) {
  throw 'Batas fungsi exportPdfChecklist tidak ditemukan. Tidak ada file yang ditulis.'
}

$newPdf = @'
  function exportPdfChecklist() {
    if (!isAdmin || !reportLoaded || reportLoading || reportLimitReached || !reportOrders.length) {
      setNotice('Muat laporan yang lengkap terlebih dahulu sebelum membuat PDF.');
      return;
    }

    const rows = ['Putra', 'Putri'].map(gender => {
      const ordersForGender = reportOrders.filter(order => order.customer.gender === gender);
      if (!ordersForGender.length) return '';
      const body = ordersForGender.map(order => {
        const menu = order.items
          .map(item => `${escapeHtml(item.name)} x ${Number(item.qty)}`)
          .join('<br>');
        return `<tr>
          <td>${escapeHtml(order.customer.name)}</td>
          <td>${escapeHtml(order.customer.className)}</td>
          <td>${escapeHtml(order.customer.dorm)}</td>
          <td class="menu-cell">${menu}</td>
          <td class="check-cell"><span class="check-box" aria-label="Belum dicek"></span></td>
        </tr>`;
      }).join('');
      return `<section class="gender-section">
        <h2>Santri ${gender}</h2>
        <table>
          <colgroup>
            <col class="col-name"><col class="col-class"><col class="col-dorm">
            <col class="col-menu"><col class="col-check">
          </colgroup>
          <thead><tr>
            <th>Nama santri</th><th>Kelas</th><th>Asrama</th>
            <th>Menu dan jumlah</th><th>Ceklis</th>
          </tr></thead>
          <tbody>${body}</tbody>
        </table>
      </section>`;
    }).join('');

    // HTML ini hanya berisi dokumen ceklis, tanpa komponen halaman aplikasi.
    // Preview ditampilkan terlebih dahulu; pengguna menekan tombol cetak secara langsung.
    const html = `<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Warung Darul Ilmi – Ceklis Distribusi</title>
<style>
  *{box-sizing:border-box}
  html,body{margin:0;padding:0;background:#fff;color:#17251e}
  body{font:10pt/1.35 Arial,Helvetica,sans-serif}
  .document{width:100%;max-width:190mm;margin:0 auto;padding:0}
  .toolbar{display:flex;justify-content:flex-end;gap:8px;margin:0 auto 14px;max-width:190mm}
  .print-button{border:0;border-radius:8px;padding:11px 16px;background:#174737;color:#fff;font:700 14px Arial,sans-serif;cursor:pointer}
  h1{font-size:17pt;line-height:1.2;margin:0 0 5px;font-weight:700}
  .period{margin:0 0 18px;color:#4f5d55;font-size:9pt}
  .gender-section{margin:17px 0 22px}
  h2{font-size:12pt;margin:0 0 8px;padding:0 5px;break-after:avoid-page;page-break-after:avoid}
  table{width:100%;border-collapse:collapse;table-layout:fixed}
  col.col-name{width:23%} col.col-class{width:12%} col.col-dorm{width:16%}
  col.col-menu{width:39%} col.col-check{width:10%}
  th,td{border:1px solid #9eaaa2;padding:7px 6px;text-align:left;vertical-align:middle;overflow-wrap:anywhere}
  th{background:#f2f4f1;font-weight:700}
  td.menu-cell{line-height:1.55}
  th:last-child,td.check-cell{text-align:center}
  .check-box{display:inline-block;width:15px;height:19px;border:1.4px solid #26382d;vertical-align:middle}
  tr{break-inside:avoid;page-break-inside:avoid}
  thead{display:table-header-group}
  .empty{padding:12px;border:1px solid #aaa}
  @page{size:A4 portrait;margin:12mm 10mm}
  @media screen{body{padding:12px}.document{max-width:190mm}}
  @media print{
    html,body{width:auto;background:#fff!important}
    body{margin:0;padding:0;-webkit-print-color-adjust:exact;print-color-adjust:exact}
    .toolbar{display:none!important}
    .document{max-width:none;width:100%}
    .gender-section{margin:12px 0 18px}
    h1{font-size:16pt} h2{font-size:11pt} th,td{padding:6px 5px}
  }
</style>
</head>
<body>
  <div class="toolbar">
    <button class="print-button" type="button" onclick="window.print()">Cetak / Simpan sebagai PDF</button>
  </div>
  <main class="document">
    <h1>Warung Darul Ilmi – Ceklis Distribusi</h1>
    <p class="period">Periode: ${escapeHtml(reportPeriodLabel())} | Jumlah pesanan: ${reportOrders.length}</p>
    ${rows || '<p class="empty">Tidak ada pesanan.</p>'}
  </main>
</body>
</html>`;

    // Pop-up dibuka langsung saat klik tombol Ekspor PDF (bukan setelah proses async).
    const printWindow = window.open('', '_blank');
    if (!printWindow) {
      setNotice('Browser memblokir jendela pratinjau. Izinkan pop-up untuk situs Warung Darul Ilmi, lalu tekan Ekspor PDF kembali.');
      return;
    }
    try {
      printWindow.document.open();
      printWindow.document.write(html);
      printWindow.document.close();
      setNotice('Pratinjau ceklis siap. Tekan tombol Cetak / Simpan sebagai PDF pada tab yang terbuka.');
    } catch (error) {
      try { printWindow.close(); } catch {}
      setNotice(`Gagal menyiapkan pratinjau PDF: ${error?.message || error}`);
    }
  }

'@

$app = $app.Substring(0, $start) + $newPdf + $app.Substring($end)

# Validasi akhir: hapus harus ada di laporan; PDF tidak lagi auto-print saat load.
$reportLine = $app.Split("`n") | Where-Object { $_.Contains("page==='reports'&&isAdmin&&") } | Select-Object -First 1
if (!$reportLine -or !$reportLine.Contains('onDelete={softDeleteOrder}')) {
  throw 'Validasi gagal: tombol hapus Laporan belum tersambung.'
}
if (!$app.Contains('const target = [orders, reportOrders, distributionRows]') -or !$app.Contains('refreshTasks.push(loadReportOrders())')) {
  throw 'Validasi gagal: pencarian target / refresh Laporan tidak ditemukan.'
}
if (!$app.Contains('onclick="window.print()"') -or $app.Contains('window.addEventListener(''load'',()=>{setTimeout(()=>{window.focus();window.print();}')) {
  throw 'Validasi gagal: kontrol cetak manual / penghapusan auto-print tidak sesuai.'
}

# Tulis file hanya setelah semua validasi lolos, simpan backup sebelumnya.
$backup = "$appPath.before-fix-pdf-report-delete"
Copy-Item $appPath $backup -Force
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($appPath, $app, $utf8NoBom)

Write-Host ''
Write-Host 'Perbaikan PDF mobile dan hapus pesanan pada Laporan berhasil diterapkan.' -ForegroundColor Green
Write-Host "Backup dibuat: $backup"
Write-Host 'Selanjutnya jalankan: npm run build'

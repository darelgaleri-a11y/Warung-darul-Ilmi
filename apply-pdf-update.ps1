$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appPath = Join-Path $root 'src\App.jsx'
if (!(Test-Path $appPath)) { throw 'src\App.jsx tidak ditemukan. Ekstrak ZIP di folder utama repository (folder yang berisi package.json).' }
$app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)
$startMarker = '  function exportPdfChecklist() {'
$endMarker = '  async function exportTxtSummary() {'
$start = $app.IndexOf($startMarker, [System.StringComparison]::Ordinal)
$end = $app.IndexOf($endMarker, [System.StringComparison]::Ordinal)
if ($start -lt 0 -or $end -lt 0 -or $end -le $start) { throw 'Fungsi ekspor PDF tidak cocok dengan versi branch app yang diperiksa. Tidak ada file yang diubah.' }
$oldFunction = $app.Substring($start, $end - $start)
if (!$oldFunction.Contains('frame.srcdoc = html;')) { throw 'Isi fungsi ekspor PDF berbeda dari versi yang diperiksa. Tidak ada file yang diubah.' }
$newFunction = @'
  function exportPdfChecklist() {
    if (!isAdmin || !reportLoaded || reportLoading || reportLimitReached || !reportOrders.length) {
      setNotice('Muat laporan yang lengkap terlebih dahulu sebelum membuat PDF.');
      return;
    }

    const rows = ['Putra', 'Putri'].map(gender => {
      const ordersForGender = reportOrders.filter(order => order.customer.gender === gender);
      if (!ordersForGender.length) return '';
      const body = ordersForGender.map(order => {
        const menu = order.items.map(item => `${escapeHtml(item.name)} x ${Number(item.qty)}`).join('<br>');
        return `<tr><td>${escapeHtml(order.customer.name)}</td><td>${escapeHtml(order.customer.className)}</td><td>${escapeHtml(order.customer.dorm)}</td><td class="menu-cell">${menu}</td><td class="check-cell"><span class="check-box" aria-label="Belum dicek"></span></td></tr>`;
      }).join('');
      return `<section class="gender-section"><h2>Santri ${gender}</h2><table><colgroup><col class="col-name"><col class="col-class"><col class="col-dorm"><col class="col-menu"><col class="col-check"></colgroup><thead><tr><th>Nama santri</th><th>Kelas</th><th>Asrama</th><th>Menu dan jumlah</th><th>Ceklis</th></tr></thead><tbody>${body}</tbody></table></section>`;
    }).join('');

    const html = `<!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Ceklis Distribusi Warung Darul Ilmi</title><style>
      *{box-sizing:border-box}html,body{margin:0;padding:0;background:#fff;color:#17251e}body{font:10pt/1.35 Arial,Helvetica,sans-serif}.document{width:100%;max-width:190mm;margin:0 auto;padding:0}h1{font-size:17pt;line-height:1.2;margin:0 0 5px;font-weight:700}.period{margin:0 0 18px;color:#4f5d55;font-size:9pt}.gender-section{margin:17px 0 22px}h2{font-size:12pt;margin:0 0 8px;padding:0 5px;break-after:avoid-page;page-break-after:avoid}table{width:100%;border-collapse:collapse;table-layout:fixed}col.col-name{width:23%}col.col-class{width:12%}col.col-dorm{width:16%}col.col-menu{width:39%}col.col-check{width:10%}th,td{border:1px solid #9eaaa2;padding:7px 6px;text-align:left;vertical-align:middle;overflow-wrap:anywhere}th{background:#f2f4f1;font-weight:700}td.menu-cell{line-height:1.55}th:last-child,td.check-cell{text-align:center}.check-box{display:inline-block;width:15px;height:19px;border:1.4px solid #26382d;vertical-align:middle}tr{break-inside:avoid;page-break-inside:avoid}thead{display:table-header-group}tfoot{display:table-footer-group}.empty{padding:12px;border:1px solid #aaa}@page{size:A4 portrait;margin:12mm 10mm}@media screen{body{padding:12px}.document{max-width:190mm}}@media print{html,body{width:auto;background:#fff!important}body{margin:0;padding:0;-webkit-print-color-adjust:exact;print-color-adjust:exact}.document{max-width:none;width:100%}.gender-section{margin:12px 0 18px}h1{font-size:16pt}h2{font-size:11pt}th,td{padding:6px 5px}}
    </style></head><body><main class="document"><h1>Warung Darul Ilmi – Ceklis Distribusi</h1><p class="period">Periode: ${escapeHtml(reportPeriodLabel())} | Jumlah pesanan: ${reportOrders.length}</p>${rows || '<p class="empty">Tidak ada pesanan.</p>'}</main><script>window.addEventListener('load',()=>{setTimeout(()=>{window.focus();window.print();},350);});window.addEventListener('afterprint',()=>{setTimeout(()=>window.close(),250);});</script></body></html>`;

    const printWindow = window.open('', '_blank');
    if (!printWindow) {
      setNotice('Browser memblokir jendela PDF. Izinkan pop-up untuk situs Warung Darul Ilmi, lalu tekan Ekspor PDF kembali.');
      return;
    }
    try {
      printWindow.document.open();
      printWindow.document.write(html);
      printWindow.document.close();
      setNotice('Dokumen ceklis dibuka. Pilih Simpan sebagai PDF pada menu cetak browser.');
    } catch (error) {
      printWindow.close();
      setNotice(`Gagal menyiapkan PDF: ${error?.message || error}`);
    }
  }

'@
$updated = $app.Substring(0, $start) + $newFunction + $app.Substring($end)
$backup = "$appPath.before-mobile-pdf-update"
Copy-Item $appPath $backup -Force
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($appPath, $updated, $utf8NoBom)
Write-Host 'Perbaikan ekspor PDF mobile berhasil diterapkan.' -ForegroundColor Green
Write-Host "Backup dibuat: $backup"
Write-Host 'Selanjutnya jalankan: npm run build'

$ErrorActionPreference = 'Stop'

$root = Get-Location
$appPath = Join-Path $root 'src\App.jsx'
if (-not (Test-Path $appPath)) {
    throw 'File src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek branch app.'
}

$content = Get-Content -LiteralPath $appPath -Raw
$lineEnding = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
$normalized = $content.Replace("`r`n", "`n")

$oldBlock = @'
      const result = Array.isArray(data) ? data[0] : data;
      const validResult = result && result.order_id && result.order_number && result.delivery_date && Number.isFinite(Number(result.total_amount));
      if (!validResult) {
        if (whatsappTab && !whatsappTab.closed) whatsappTab.close();
        setNotice('Server tidak mengembalikan detail nomor pesanan yang lengkap. Pesanan mungkin sudah tersimpan. Jangan langsung mengirim ulang; periksa antrean kasir atau hubungi admin terlebih dahulu.');
        return;
      }
'@
$newBlock = @'
      // RPC create_guest_order returns exactly one row. Reject empty or multiple rows
      // before any order fields are read or the shopping cart is cleared.
      const responseRows = Array.isArray(data)
        ? data
        : (data && typeof data === 'object' ? [data] : []);
      if (responseRows.length !== 1) {
        if (whatsappTab && !whatsappTab.closed) whatsappTab.close();
        setNotice('Respons server tidak valid: detail pesanan kosong atau berjumlah lebih dari satu. Pesanan mungkin sudah tersimpan. Jangan kirim ulang dulu; periksa antrean kasir atau hubungi admin.');
        return;
      }

      const result = responseRows[0];
      const orderIdValid = typeof result?.order_id === 'string'
        && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result.order_id);
      const orderNumberValid = typeof result?.order_number === 'string'
        && result.order_number.trim().length > 0;
      const deliveryDateText = typeof result?.delivery_date === 'string' ? result.delivery_date : '';
      const deliveryDateValid = /^\d{4}-\d{2}-\d{2}$/.test(deliveryDateText)
        && !Number.isNaN(Date.parse(`${deliveryDateText}T00:00:00Z`))
        && new Date(`${deliveryDateText}T00:00:00Z`).toISOString().slice(0, 10) === deliveryDateText;
      const totalValue = (typeof result?.total_amount === 'number' || typeof result?.total_amount === 'string')
        && String(result.total_amount).trim() !== ''
        ? Number(result.total_amount)
        : Number.NaN;
      const totalValid = Number.isSafeInteger(totalValue) && totalValue >= 0;

      if (!orderIdValid || !orderNumberValid || !deliveryDateValid || !totalValid) {
        if (whatsappTab && !whatsappTab.closed) whatsappTab.close();
        setNotice('Respons server belum lengkap atau formatnya tidak valid. Pesanan mungkin sudah tersimpan. Jangan kirim ulang dulu; periksa antrean kasir menggunakan nama dan waktu pemesanan, atau hubungi admin.');
        return;
      }
'@

$oldBlock = $oldBlock.Trim("`r", "`n")
$newBlock = $newBlock.Trim("`r", "`n")
$count = ([regex]::Matches($normalized, [regex]::Escape($oldBlock))).Count
if ($count -ne 1) {
    throw "Bagian validasi RPC yang diharapkan ditemukan $count kali (seharusnya tepat 1). File tidak diubah. Pastikan src\App.jsx berasal dari branch app terbaru dan perubahan WhatsApp sebelumnya tetap ada."
}

foreach ($required in @('const [orderSubmitting, setOrderSubmitting] = useState(false);', 'const [whatsAppFallbackUrl, setWhatsAppFallbackUrl] = useState', 'whatsappTab.location.replace(whatsappUrl)', 'setCart([]);')) {
    if (-not $normalized.Contains($required)) {
        throw "Pemeriksaan keamanan gagal: bagian '$required' tidak ditemukan. File tidak diubah."
    }
}

$backupPath = "$appPath.bak-sebelum-validasi-rpc"
if (Test-Path $backupPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$appPath.bak-sebelum-validasi-rpc-$stamp"
}
Copy-Item -LiteralPath $appPath -Destination $backupPath

$updated = $normalized.Replace($oldBlock, $newBlock)
$updated = $updated.Replace("`n", $lineEnding)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($appPath, $updated, $utf8NoBom)

$verify = Get-Content -LiteralPath $appPath -Raw
if (-not $verify.Contains('const responseRows = Array.isArray(data)')) {
    Copy-Item -LiteralPath $backupPath -Destination $appPath -Force
    throw 'Validasi setelah penulisan gagal. File lama sudah dipulihkan dari cadangan.'
}
if ($verify.Contains('const validResult = result && result.order_id && result.order_number')) {
    Copy-Item -LiteralPath $backupPath -Destination $appPath -Force
    throw 'Validasi lama masih ditemukan. File lama sudah dipulihkan dari cadangan.'
}

Write-Host 'BERHASIL: validasi hasil RPC diperbarui pada src\App.jsx.' -ForegroundColor Green
Write-Host "Cadangan: $backupPath"
Write-Host 'Keranjang hanya dikosongkan setelah tepat satu hasil RPC yang valid diperoleh.'

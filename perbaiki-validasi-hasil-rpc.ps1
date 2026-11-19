$ErrorActionPreference = 'Stop'

$projectRoot = (Get-Location).Path
$appPath = Join-Path $projectRoot 'src\App.jsx'

if (-not (Test-Path -LiteralPath $appPath)) {
    throw "File src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek Warung Darul Ilmi."
}

$encoding = New-Object System.Text.UTF8Encoding($false)
$source = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)

if ($source.Contains('const rpcRows = Array.isArray(data) ? data : [];')) {
    Write-Host 'Validasi hasil RPC yang lebih ketat sudah terpasang. Tidak ada perubahan.' -ForegroundColor Yellow
    exit 0
}

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
      // The RPC returns exactly one row because create_guest_order is RETURNS TABLE.
      // Never consume order fields until the response shape and every receipt field are valid.
      const rpcRows = Array.isArray(data) ? data : [];
      let result = rpcRows.length === 1 && rpcRows[0] && typeof rpcRows[0] === 'object' && !Array.isArray(rpcRows[0])
        ? rpcRows[0]
        : null;

      const orderIdIsValid = typeof result?.order_id === 'string'
        && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(result.order_id);
      const orderNumber = typeof result?.order_number === 'string' ? result.order_number.trim() : '';
      const rawDeliveryDate = typeof result?.delivery_date === 'string' ? result.delivery_date : '';
      const parsedDeliveryDate = /^\d{4}-\d{2}-\d{2}$/.test(rawDeliveryDate)
        ? new Date(`${rawDeliveryDate}T00:00:00.000Z`)
        : null;
      const deliveryDateIsValid = Boolean(parsedDeliveryDate
        && Number.isFinite(parsedDeliveryDate.getTime())
        && parsedDeliveryDate.toISOString().slice(0, 10) === rawDeliveryDate);
      const rawTotalAmount = result?.total_amount;
      const totalText = typeof rawTotalAmount === 'number'
        ? (Number.isSafeInteger(rawTotalAmount) ? String(rawTotalAmount) : '')
        : typeof rawTotalAmount === 'string' ? rawTotalAmount.trim() : '';
      const totalAmount = /^\d+$/.test(totalText) ? Number(totalText) : NaN;
      const totalAmountIsValid = Number.isSafeInteger(totalAmount) && totalAmount >= 0;
      const validResult = Boolean(result && orderIdIsValid && orderNumber && deliveryDateIsValid && totalAmountIsValid);

      if (!validResult) {
        if (whatsappTab && !whatsappTab.closed) whatsappTab.close();
        setNotice('Respons server untuk pesanan tidak lengkap atau tidak valid. Pesanan mungkin sudah tersimpan, tetapi aplikasi belum dapat memastikan nomor dan totalnya. Jangan mengirim ulang dulu; periksa antrean kasir atau hubungi admin.');
        return;
      }

      // Normalize fields only after validation; subsequent UI and WhatsApp use trusted values.
      result = { ...result, order_number: orderNumber, delivery_date: rawDeliveryDate, total_amount: totalAmount };
'@

$occurrences = ([regex]::Matches($source, [regex]::Escape($oldBlock))).Count
if ($occurrences -ne 1) {
    throw "Potongan validasi lama ditemukan $occurrences kali, bukan tepat satu kali. File tidak diubah. Pastikan src\App.jsx sudah menggunakan versi branch app terbaru."
}

$backupPath = "$appPath.bak-sebelum-validasi-rpc-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
[System.IO.File]::Copy($appPath, $backupPath, $false)

try {
    $updated = $source.Replace($oldBlock, $newBlock)
    [System.IO.File]::WriteAllText($appPath, $updated, $encoding)
    $verified = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)

    $required = @(
        'const rpcRows = Array.isArray(data) ? data : [];',
        'rpcRows.length === 1',
        'orderIdIsValid',
        'deliveryDateIsValid',
        'totalAmountIsValid',
        'result = { ...result, order_number: orderNumber, delivery_date: rawDeliveryDate, total_amount: totalAmount };'
    )
    foreach ($marker in $required) {
        if (-not $verified.Contains($marker)) {
            throw "Pemeriksaan hasil perubahan gagal pada penanda: $marker"
        }
    }
    if ($verified.Contains('const validResult = result && result.order_id && result.order_number && result.delivery_date && Number.isFinite(Number(result.total_amount));')) {
        throw 'Validasi lama masih ditemukan setelah perubahan.'
    }

    Write-Host 'Berhasil memperketat validasi hasil RPC pada src\App.jsx.' -ForegroundColor Green
    Write-Host "Cadangan dibuat: $backupPath"
    Write-Host 'File yang diubah: src\App.jsx'
    Write-Host 'Langkah berikutnya: jalankan npm run build.'
}
catch {
    [System.IO.File]::Copy($backupPath, $appPath, $true)
    throw "Perubahan gagal diverifikasi. File asli dipulihkan dari cadangan. Detail: $($_.Exception.Message)"
}

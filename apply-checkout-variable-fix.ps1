$ErrorActionPreference = 'Stop'

$root = Get-Location
$appPath = Join-Path $root 'src\App.jsx'
if (-not (Test-Path -LiteralPath $appPath)) {
    throw 'src\App.jsx tidak ditemukan. Jalankan script dari folder utama proyek yang berisi package.json.'
}

$content = [System.IO.File]::ReadAllText($appPath)
$old = @'
      if (whatsappUrl) {
        setNotice(`Pesanan ${result.order_number} tersimpan. Tekan tombol Kirim di WhatsApp untuk mengirim konfirmasi. Jika WhatsApp tidak terbuka, gunakan tombol WhatsApp pada halaman ini.`);
      } else {
'@
$new = @'
      if (whatsappWebUrl) {
        setNotice(`Pesanan ${result.order_number} tersimpan. Tekan tombol Kirim di WhatsApp untuk mengirim konfirmasi. Jika WhatsApp tidak terbuka, gunakan tombol WhatsApp pada halaman ini.`);
      } else {
'@

$count = ([regex]::Matches($content, [regex]::Escape($old))).Count
if ($count -ne 1) {
    throw "Patch dihentikan: ditemukan $count kecocokan kode lama (seharusnya tepat 1). Tidak ada file yang diubah."
}

$backupPath = "$appPath.before-whatsapp-variable-fix"
if (-not (Test-Path -LiteralPath $backupPath)) {
    Copy-Item -LiteralPath $appPath -Destination $backupPath
}
$content = $content.Replace($old, $new)
[System.IO.File]::WriteAllText($appPath, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Berhasil: whatsappUrl diganti menjadi whatsappWebUrl.' -ForegroundColor Green
Write-Host "Cadangan: $backupPath"

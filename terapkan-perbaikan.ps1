$ErrorActionPreference = 'Stop'

$file = Join-Path (Get-Location) 'src\App.jsx'
if (-not (Test-Path $file)) {
  throw 'File src\App.jsx tidak ditemukan. Jalankan skrip ini dari folder utama proyek Warung Darul Ilmi.'
}

$content = Get-Content -Raw -Path $file

$old = '<input type="password" autoComplete="off" name="settings-password-confirmation" value={settingsPassword} onChange={e=>setSettingsPassword(e.target.value)} placeholder="Masukkan password saat akan menyimpan" required/>'
$new = '<input type="password" name="settings-password-confirmation-entry" autoComplete="new-password" readOnly onFocus={e=>e.currentTarget.removeAttribute("readonly")} value={settingsPassword} onChange={e=>setSettingsPassword(e.target.value)} placeholder="Masukkan password saat akan menyimpan" required/>'

if ($content.Contains($new)) {
  Write-Host 'Perbaikan sudah diterapkan sebelumnya. Tidak ada perubahan.' -ForegroundColor Yellow
  exit 0
}

if (-not $content.Contains($old)) {
  throw 'Kolom password versi yang diharapkan tidak ditemukan. Tidak ada file yang diubah. Pastikan proyek berada pada branch app dan periksa src/App.jsx.'
}

$backup = "$file.bak"
Copy-Item -LiteralPath $file -Destination $backup -Force
$content = $content.Replace($old, $new)
Set-Content -LiteralPath $file -Value $content -Encoding UTF8 -NoNewline

Write-Host 'Perbaikan berhasil diterapkan pada src\App.jsx.' -ForegroundColor Green
Write-Host "Cadangan file lama: $backup"
Write-Host 'Langkah berikutnya: jalankan npm run build.'

$ErrorActionPreference = 'Stop'
$targetVersion = '1.0.0'

$branch = (git branch --show-current).Trim()
if ($branch -ne 'app') {
    throw "Branch aktif '$branch'. Pindah ke branch 'app' sebelum menjalankan script."
}

$status = git status --short
if ($LASTEXITCODE -ne 0) { throw 'Tidak dapat memeriksa status Git.' }
if ($status) {
    throw "Working tree tidak bersih. Simpan/commit perubahan terlebih dahulu agar aman."
}

$packagePath = Join-Path (Get-Location) 'package.json'
$readmePath  = Join-Path (Get-Location) 'README.md'
$appPath     = Join-Path (Get-Location) 'src\App.jsx'

foreach ($path in @($packagePath, $readmePath, $appPath)) {
    if (!(Test-Path $path)) { throw "File tidak ditemukan: $path" }
}

$package = Get-Content $packagePath -Raw | ConvertFrom-Json
$readme = Get-Content $readmePath -Raw
$app = Get-Content $appPath -Raw

$package.version = $targetVersion
$packageJson = $package | ConvertTo-Json -Depth 100

$readmeNew = [regex]::Replace(
    $readme,
    '(?m)^(# Warung Darul Ilmi v)\d+\.\d+\.\d+',
    ('$1' + $targetVersion),
    1
)
if ($readmeNew -eq $readme) {
    throw 'Judul versi pada README tidak ditemukan. Tidak ada file yang diubah.'
}

$appNew = [regex]::Replace(
    $app,
    '(<strong>Warung Darul Ilmi</strong>\s*<small>)v[^<]*(</small>)',
    ('$1v' + $targetVersion + '$2'),
    1
)
if ($appNew -eq $app) {
    throw 'Label versi footer aplikasi tidak ditemukan. Tidak ada file yang diubah.'
}

$backupDir = Join-Path (Get-Location) ('backup-versi-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backupDir | Out-Null
Copy-Item $packagePath, $readmePath, $appPath -Destination $backupDir

Set-Content -Path $packagePath -Value $packageJson -Encoding UTF8
Set-Content -Path $readmePath -Value $readmeNew -Encoding UTF8
Set-Content -Path $appPath -Value $appNew -Encoding UTF8

Write-Host ''
Write-Host 'Versi resmi berhasil disamakan menjadi v1.0.0.' -ForegroundColor Green
Write-Host 'File diperbarui: package.json, README.md, src\App.jsx'
Write-Host "Backup: $backupDir"
Write-Host ''
Write-Host 'Periksa perubahan dengan: git diff'
Write-Host 'Uji build dengan: npm run build'

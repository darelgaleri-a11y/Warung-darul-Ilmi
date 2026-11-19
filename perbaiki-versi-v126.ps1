$ErrorActionPreference = 'Stop'

$root = Get-Location
$requiredBranch = 'app'
$targetVersion = '1.2.6'

Write-Host "Memeriksa proyek Warung Darul Ilmi..." -ForegroundColor Cyan

if (-not (Test-Path (Join-Path $root 'package.json'))) {
    throw "package.json tidak ditemukan. Jalankan script dari folder utama proyek."
}
if (-not (Test-Path (Join-Path $root 'package-lock.json'))) {
    throw "package-lock.json tidak ditemukan. Tidak ada file yang diubah."
}
if (-not (Test-Path (Join-Path $root 'README.md'))) {
    throw "README.md tidak ditemukan. Tidak ada file yang diubah."
}

$branch = (git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne $requiredBranch) {
    throw "Branch aktif harus '$requiredBranch'. Branch saat ini: '$branch'. Tidak ada file yang diubah."
}

$status = git status --porcelain
if ($LASTEXITCODE -ne 0) { throw "Tidak dapat memeriksa status Git." }
if ($status) {
    throw "Working tree tidak bersih. Commit atau amankan perubahan lokal terlebih dahulu. Tidak ada file yang diubah."
}

$packagePath = Join-Path $root 'package.json'
$lockPath = Join-Path $root 'package-lock.json'
$readmePath = Join-Path $root 'README.md'

$package = Get-Content $packagePath -Raw | ConvertFrom-Json
$lock = Get-Content $lockPath -Raw | ConvertFrom-Json
$readme = Get-Content $readmePath -Raw

if ($package.version -ne '1.2.1' -and $package.version -ne $targetVersion) {
    throw "Versi package.json tidak sesuai kondisi audit (1.2.1 atau 1.2.6). Ditemukan: $($package.version). Tidak ada file yang diubah."
}
if ($lock.version -ne '1.2.1' -and $lock.version -ne $targetVersion) {
    throw "Versi package-lock.json tidak sesuai kondisi audit (1.2.1 atau 1.2.6). Ditemukan: $($lock.version). Tidak ada file yang diubah."
}
if ($lock.packages.''.version -ne '1.2.1' -and $lock.packages.''.version -ne $targetVersion) {
    throw "Versi root package-lock.json tidak sesuai kondisi audit. Tidak ada file yang diubah."
}
if ($readme -notmatch 'Warung Darul Ilmi v1\.2\.1|Warung Darul Ilmi v1\.2\.6') {
    throw "Judul versi README tidak cocok dengan kondisi audit. Tidak ada file yang diubah."
}

$backupDir = Join-Path $root ("backup-versi-sebelum-v126-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backupDir | Out-Null
Copy-Item $packagePath, $lockPath, $readmePath -Destination $backupDir

$package.version = $targetVersion
$lock.version = $targetVersion
$lock.packages.''.version = $targetVersion
$readme = $readme -replace 'v1\.2\.1', 'v1.2.6'

$package | ConvertTo-Json -Depth 100 | Set-Content -Path $packagePath -Encoding utf8
$lock | ConvertTo-Json -Depth 100 | Set-Content -Path $lockPath -Encoding utf8
Set-Content -Path $readmePath -Value $readme -Encoding utf8

Write-Host ""
Write-Host "Berhasil menyamakan versi resmi menjadi v1.2.6." -ForegroundColor Green
Write-Host "File diperbarui: package.json, package-lock.json, README.md"
Write-Host "src/App.jsx tidak diubah karena footer sudah v1.2.6."
Write-Host "Backup tersimpan di: $backupDir"
Write-Host ""
Write-Host "Verifikasi:"
(Get-Content $packagePath -Raw | ConvertFrom-Json).version
(Get-Content $lockPath -Raw | ConvertFrom-Json).version
Select-String -Path $readmePath -Pattern 'Warung Darul Ilmi v1\.2\.6'
Write-Host ""
Write-Host "Selanjutnya jalankan: npm run build"

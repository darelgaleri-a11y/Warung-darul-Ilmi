$ErrorActionPreference = "Stop"
$guide = Join-Path (Get-Location) "supabase\migrations\README-MIGRATION-ORDER.txt"
if (-not (Test-Path -LiteralPath $guide)) {
    throw "Panduan tidak ditemukan. Ekstrak ZIP dengan struktur folder."
}
Write-Host "Panduan migration Warung Darul Ilmi:" -ForegroundColor Green
Get-Content -LiteralPath $guide
Write-Host ""
Write-Host "Pemeriksaan selesai. Tidak ada SQL atau database yang diubah." -ForegroundColor Yellow

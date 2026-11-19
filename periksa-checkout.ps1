$ErrorActionPreference = "Stop"
$app = Join-Path (Get-Location) "src\App.jsx"
$sql = Join-Path (Get-Location) "supabase\migrations\202611180003_align_guest_checkout_rpc.sql"

if (-not (Test-Path $app)) { throw "src\App.jsx tidak ditemukan. Jalankan dari folder utama proyek." }
if (-not (Test-Path $sql)) { throw "Migration checkout tidak ditemukan. Ekstrak ZIP dengan struktur folder." }

$appText = [System.IO.File]::ReadAllText($app, [System.Text.Encoding]::UTF8)
if ($appText -notmatch "p_access_token\s*:\s*accessToken") { throw "App.jsx tidak mengirim p_access_token." }
if ($appText -notmatch "rpc\('create_guest_order'") { throw "Pemanggilan create_guest_order tidak ditemukan." }

$sqlText = [System.IO.File]::ReadAllText($sql, [System.Text.Encoding]::UTF8)
foreach ($needle in @("p_access_token text", "guest_access_token_hash", "extensions.digest", "create_guest_order(text,text,text,text,text,text,jsonb,text)")) {
    if (-not $sqlText.Contains($needle)) { throw "Migration tidak lengkap: $needle" }
}
Write-Host "OK: App.jsx mengirim p_access_token." -ForegroundColor Green
Write-Host "OK: migration menerima 8 parameter dan menyimpan hash token." -ForegroundColor Green
Write-Host "Tidak ada file aplikasi yang diubah oleh skrip pemeriksaan ini."

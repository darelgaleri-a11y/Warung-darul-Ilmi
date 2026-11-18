$ErrorActionPreference = "Stop"

$target = Join-Path (Get-Location) "src\App.jsx"
if (-not (Test-Path -LiteralPath $target)) {
    throw "src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek."
}

$backup = "$target.bak-katalog-emoji"
Copy-Item -LiteralPath $target -Destination $backup -Force

$content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)

function U([int[]]$Codes) {
    $builder = [System.Text.StringBuilder]::new()
    foreach ($code in $Codes) {
        [void]$builder.Append([char]::ConvertFromUtf32($code))
    }
    return $builder.ToString()
}

$content = $content.Replace("ðŸ—", (U @(0x1F357)))
$content = $content.Replace("ðŸ›", (U @(0x1F35B)))
$content = $content.Replace("ðŸœ", (U @(0x1F35C)))
$content = $content.Replace("ðŸ§‹", (U @(0x1F9CB)))
$content = $content.Replace("ðŸ’§", (U @(0x1F4A7)))
$content = $content.Replace("ðŸ¥", (U @(0x1F950)))
$content = $content.Replace("ðŸ½ï¸", (U @(0x1F37D, 0xFE0F)))
$content = $content.Replace("ðŸ›’", (U @(0x1F6D2)))

$content = $content.Replace("Contoh produk â€” ubah melalui database/admin.", "Contoh produk - ubah melalui database/admin.")
$content = $content.Replace("Memuat katalogâ€¦", "Memuat katalog...")
$content = $content.Replace("Ã—", "×")
$content = $content.Replace("â†‘", "↑")
$content = $content.Replace("â†’", "→")
$content = $content.Replace("â€”", "-")
$content = $content.Replace("Â·", "·")

[System.IO.File]::WriteAllText($target, $content, [System.Text.UTF8Encoding]::new($false))

Write-Host "Perbaikan karakter katalog selesai." -ForegroundColor Green
Write-Host "Cadangan dibuat: $backup"
Write-Host "Jalankan npm run build untuk memeriksa aplikasi."

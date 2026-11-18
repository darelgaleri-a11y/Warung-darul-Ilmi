# Jalankan dari folder utama proyek Warung Darul Ilmi.
$ErrorActionPreference = "Stop"
$target = Join-Path (Get-Location) "src\App.jsx"

if (-not (Test-Path $target)) {
    throw "src\App.jsx tidak ditemukan. Pastikan PowerShell berada di folder utama proyek."
}

$backup = "$target.bak-tampilan"
Copy-Item $target $backup -Force

$content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)

# Perbaiki emoji yang sebelumnya tersimpan sebagai teks mojibake.
$replacements = [ordered]@{
    "ðŸ—" = "🍗"
    "ðŸ›" = "🍛"
    "ðŸœ" = "🍜"
    "ðŸ§‹" = "🧋"
    "ðŸ’§" = "💧"
    "ðŸ¥" = "🥐"
    "ðŸ½ï¸" = "🍽️"
    "ðŸ›’" = "🛒"
    "â€”" = "—"
    "Â·" = "·"
    "â€¦" = "…"
    "Ã—" = "×"
    "â†’" = "→"
    "â€œ" = "“"
    "â€" = "”"
    "â€™" = "’"
}

foreach ($key in $replacements.Keys) {
    $content = $content.Replace($key, $replacements[$key])
}

[System.IO.File]::WriteAllText($target, $content, [System.Text.UTF8Encoding]::new($false))

Write-Host "Perbaikan karakter dan emoji selesai." -ForegroundColor Green
Write-Host "Cadangan file: $backup"
Write-Host ""
Write-Host "Selanjutnya jalankan: npm run build"

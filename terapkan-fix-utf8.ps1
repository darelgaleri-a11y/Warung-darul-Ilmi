$ErrorActionPreference = "Stop"

$root = (Get-Location).Path
$appPath = Join-Path $root "src\App.jsx"
if (-not (Test-Path -LiteralPath $appPath)) {
    throw "src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek."
}

$original = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)
$backup = "$appPath.bak-sebelum-fix-utf8"
Copy-Item -LiteralPath $appPath -Destination $backup -Force

$map = @(
    @(([char]0x00E2).ToString() + [char]0x20AC + [char]0x201D, [char]0x2014),
    @(([char]0x00E2).ToString() + [char]0x20AC + [char]0x00A6, [char]0x2026),
    @(([char]0x00E2).ToString() + [char]0x00C2 + [char]0x2019, [char]0x2192),
    @(([char]0x00C2).ToString() + [char]0x00B7, [char]0x00B7),
    @(([char]0x00C3).ToString() + [char]0x2014, [char]0x00D7),
    @(([char]0x00E2).ToString() + [char]0x2020 + [char]0x2019, [char]0x2192),
    @(([char]0x00E2).ToString() + [char]0x2020 + [char]0x2018, [char]0x2190),
    @(([char]0x00E2).ToString() + [char]0x02C6 + [char]0x2019, [char]0x2191),
    @(([char]0x00E2).ToString() + [char]0x20AC + [char]0x0153, [char]0x201C),
    @(([char]0x00E2).ToString() + [char]0x20AC + [char]0x2122, [char]0x2019)
)
$content = $original
foreach ($pair in $map) {
    $content = $content.Replace([string]$pair[0], [string]$pair[1])
}

$mojibake = @(
    @(([char]0x00F0).ToString()+[char]0x0178+[char]0x008D+[char]0x2017, [char]::ConvertFromUtf32(0x1F357)),
    @(([char]0x00F0).ToString()+[char]0x0178+[char]0x008D+[char]0x201B, [char]::ConvertFromUtf32(0x1F35B)),
    @(([char]0x00F0).ToString()+[char]0x0178+[char]0x008D+[char]0x0153, [char]::ConvertFromUtf32(0x1F35C)),
    @(([char]0x00F0).ToString()+[char]0x0178+[char]0x00A7+[char]0x2039, [char]::ConvertFromUtf32(0x1F9CB)),
    @(([char]0x00F0).ToString()+[char]0x0178+[char]0x2019+[char]0x00A7, [char]::ConvertFromUtf32(0x1F4A7)),
    @(([char]0x00F0).ToString()+[char]0x0178+[char]0x00A5+[char]0x0090, [char]::ConvertFromUtf32(0x1F950)),
    @(([char]0x00F0).ToString()+[char]0x0178+[char]0x008D+[char]0x00BD+[char]0x00EF+[char]0x00B8+[char]0x008F, [char]::ConvertFromUtf32(0x1F37D)+[char]::ConvertFromUtf32(0xFE0F)),
    @(([char]0x00F0).ToString()+[char]0x0178+[char]0x203A+[char]0x2019, [char]::ConvertFromUtf32(0x1F6D2))
)
foreach ($pair in $mojibake) {
    $content = $content.Replace([string]$pair[0], [string]$pair[1])
}

# Replace footer Arabic text with valid Unicode using PowerShell code points.
$footer = [char]::ConvertFromUtf32(0x0628)+[char]::ConvertFromUtf32(0x0650)+[char]::ConvertFromUtf32(0x0633)+[char]::ConvertFromUtf32(0x0652)+[char]::ConvertFromUtf32(0x0645)+[char]::ConvertFromUtf32(0x0650)+[char]::ConvertFromUtf32(0x0020)+[char]::ConvertFromUtf32(0x0627)+[char]::ConvertFromUtf32(0x0644)+[char]::ConvertFromUtf32(0x0644)+[char]::ConvertFromUtf32(0x064E)+[char]::ConvertFromUtf32(0x0647)+[char]::ConvertFromUtf32(0x0650)
$content = [regex]::Replace($content, '<span className="footer-note">.*?</span>', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) '<span className="footer-note">' + $footer + '</span>' })

[System.IO.File]::WriteAllText($appPath, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "App.jsx berhasil disimpan ulang sebagai UTF-8." -ForegroundColor Green
Write-Host "Cadangan dibuat: $backup"
Write-Host "Selanjutnya jalankan: npm run build"

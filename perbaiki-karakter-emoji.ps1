$ErrorActionPreference = "Stop"

function New-TextFromCodePoints([int[]]$codePoints) {
    $builder = [System.Text.StringBuilder]::new()
    foreach ($point in $codePoints) {
        if ($point -le 0xFFFF) {
            [void]$builder.Append([char]$point)
        } else {
            [void]$builder.Append([char]::ConvertFromUtf32($point))
        }
    }
    return $builder.ToString()
}

$target = Join-Path (Get-Location) "src\App.jsx"
if (-not (Test-Path -LiteralPath $target)) {
    throw "src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek."
}

$content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
$backup = "$target.bak-sebelum-fix-karakter-emoji"
Copy-Item -LiteralPath $target -Destination $backup -Force

# Each pair is built from Unicode code points so this script stays ASCII-only.
$replacements = @(
    @{ Bad = @(0x00E2,0x20AC,0x201D); Good = @(0x2014) },                         # em dash
    @{ Bad = @(0x00F0,0x0178,0x008D,0x2014); Good = @(0x1F357) },                  # poultry leg
    @{ Bad = @(0x00F0,0x0178,0x008D,0x203A); Good = @(0x1F35B) },                  # curry rice
    @{ Bad = @(0x00F0,0x0178,0x008D,0x0153); Good = @(0x1F35C) },                  # steaming bowl
    @{ Bad = @(0x00F0,0x0178,0x00A7,0x2039); Good = @(0x1F9CB) },                  # bubble tea
    @{ Bad = @(0x00F0,0x0178,0x2019,0x00A7); Good = @(0x1F4A7) },                 # water drop
    @{ Bad = @(0x00F0,0x0178,0x00A5,0x0090); Good = @(0x1F950) },                  # croissant
    @{ Bad = @(0x00F0,0x0178,0x008D,0x00BD,0x00EF,0x00B8,0x008F); Good = @(0x1F37D,0xFE0F) }, # plate
    @{ Bad = @(0x00C2,0x00B7); Good = @(0x00B7) },                                 # middle dot
    @{ Bad = @(0x00C3,0x2014); Good = @(0x00D7) },                                # multiplication sign
    @{ Bad = @(0x00E2,0x20AC,0x00A6); Good = @(0x2026) },                         # ellipsis
    @{ Bad = @(0x00E2,0x0153,0x00A6); Good = @(0x2726) },                         # four-point star
    @{ Bad = @(0x00E2,0x0153,0x00A7); Good = @(0x2727) },                         # sparkle
    @{ Bad = @(0x00F0,0x0178,0x203A,0x2019); Good = @(0x1F6D2) },                 # shopping trolley
    @{ Bad = @(0x00E2,0x02C6,0x2019); Good = @(0x2212) },                         # minus
    @{ Bad = @(0x00E2,0x2020,0x2019); Good = @(0x2192) },                         # right arrow
    @{ Bad = @(0x00E2,0x2020,0x2018); Good = @(0x2191) },                         # up arrow
    @{ Bad = @(0x00E2,0x0153,0x201C); Good = @(0x2713) },                         # check mark
    @{ Bad = @(0x00D9,0x02C6); Good = @(0x0648) },                                # Arabic waw in footer logo
    @{ Bad = @(0x00E2,0x2020,0x0090); Good = @(0x2190) }                          # left arrow
)

$totalReplacements = 0
foreach ($item in $replacements) {
    $badText = New-TextFromCodePoints $item.Bad
    $goodText = New-TextFromCodePoints $item.Good
    $count = ([regex]::Matches($content, [regex]::Escape($badText))).Count
    if ($count -gt 0) {
        $content = $content.Replace($badText, $goodText)
        $totalReplacements += $count
    }
}

# Confirm that none of the known broken sequences remain.
$remaining = @()
foreach ($item in $replacements) {
    $badText = New-TextFromCodePoints $item.Bad
    if ($content.Contains($badText)) { $remaining += $item.Bad }
}
if ($remaining.Count -gt 0) {
    throw "Masih ada pola encoding rusak yang dikenal. File asli tetap tersedia pada backup."
}

# Save as UTF-8 without BOM.
[System.IO.File]::WriteAllText(
    $target,
    $content,
    [System.Text.UTF8Encoding]::new($false)
)

# Read back to validate the written file.
$check = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
if ($check -cne $content) {
    throw "Pemeriksaan baca ulang gagal. Pulihkan dari file backup."
}

Write-Host ""
Write-Host "BERHASIL: karakter dan emoji yang rusak telah diperbaiki." -ForegroundColor Green
Write-Host "Jumlah penggantian: $totalReplacements"
Write-Host "File diperbarui: src\App.jsx"
Write-Host "Cadangan asli: $backup"
Write-Host ""
Write-Host "Berikutnya jalankan: npm run build"

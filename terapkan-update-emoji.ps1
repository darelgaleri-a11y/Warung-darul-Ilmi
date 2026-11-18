$ErrorActionPreference = "Stop"

$target = Join-Path (Get-Location) "src\App.jsx"
if (-not (Test-Path -LiteralPath $target)) {
    throw "src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek."
}

$backup = "$target.bak-sebelum-perbaikan-encoding"
Copy-Item -LiteralPath $target -Destination $backup -Force

$content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

# Reverse Windows-1252/Latin-1 mojibake bytes without putting non-ASCII
# characters inside this PowerShell file.
$specialMap = @{
    0x0152 = 0x8C
    0x0153 = 0x9C
    0x0160 = 0x8A
    0x0161 = 0x9A
    0x0178 = 0x9F
    0x017D = 0x8E
    0x017E = 0x9E
    0x0192 = 0x83
    0x02C6 = 0x88
    0x02DC = 0x98
    0x20AC = 0x80
    0x201A = 0x82
    0x201E = 0x84
    0x2026 = 0x85
    0x2020 = 0x86
    0x2021 = 0x87
    0x2030 = 0x89
    0x2039 = 0x8B
    0x2018 = 0x91
    0x2019 = 0x92
    0x201C = 0x93
    0x201D = 0x94
    0x2022 = 0x95
    0x2013 = 0x96
    0x2014 = 0x97
    0x2122 = 0x99
    0x203A = 0x9B
}

$markerCodePoints = @(0x00F0, 0x00C3, 0x00C2, 0x00E2, 0x0178, 0x20AC, 0x2122)

$evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
    param($match)

    $run = $match.Value
    $hasMarker = $false
    $bytes = [System.Collections.Generic.List[byte]]::new()

    foreach ($ch in $run.ToCharArray()) {
        $code = [int][char]$ch
        if ($markerCodePoints -contains $code) { $hasMarker = $true }

        if ($code -le 0x00FF) {
            $bytes.Add([byte]$code)
        }
        elseif ($specialMap.ContainsKey($code)) {
            $bytes.Add([byte]$specialMap[$code])
        }
        else {
            return $run
        }
    }

    if (-not $hasMarker) { return $run }

    try {
        return $strictUtf8.GetString($bytes.ToArray())
    }
    catch {
        return $run
    }
}

$content = [System.Text.RegularExpressions.Regex]::Replace(
    $content,
    '[^\x00-\x7F]+',
    $evaluator
)

[System.IO.File]::WriteAllText(
    $target,
    $content,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Perbaikan encoding src\App.jsx selesai." -ForegroundColor Green
Write-Host "Cadangan lama: $backup"
Write-Host "Lanjutkan dengan menjalankan: npm run build"

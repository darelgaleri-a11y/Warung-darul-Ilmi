$ErrorActionPreference = 'Stop'

function From-B64([string]$Value) {
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Value))
}

$projectRoot = (Get-Location).Path
$targetPath = Join-Path $projectRoot 'src\App.jsx'
if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    throw 'File src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek Warung Darul Ilmi.'
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$source = [System.IO.File]::ReadAllText($targetPath, [System.Text.Encoding]::UTF8)
$original = $source

# Pasangan teks rusak dan penggantinya dikodekan Base64 agar file skrip ini
# tetap ASCII dan tidak rusak saat dibuka oleh Windows PowerShell.
$replacements = @(
    @{ From='Q29udG9oIHByb2R1ayDDouKCrOKAnSB1YmFoIG1lbGFsdWkgZGF0YWJhc2UvYWRtaW4u'; To='Q29udG9oIHByb2R1ayAtIHViYWggbWVsYWx1aSBkYXRhYmFzZS9hZG1pbi4=' },
    @{ From='J8OwxbjCjeKAlCc='; To='U3RyaW5nLmZyb21Db2RlUG9pbnQoMHgxRjM1Nyk=' },
    @{ From='J8OwxbjCjeKAuic='; To='U3RyaW5nLmZyb21Db2RlUG9pbnQoMHgxRjM1Qik=' },
    @{ From='J8OwxbjCjcWTJw=='; To='U3RyaW5nLmZyb21Db2RlUG9pbnQoMHgxRjM1Qyk=' },
    @{ From='J8OwxbjCp+KAuSc='; To='U3RyaW5nLmZyb21Db2RlUG9pbnQoMHgxRjlDQik=' },
    @{ From='J8OwxbjigJnCpyc='; To='U3RyaW5nLmZyb21Db2RlUG9pbnQoMHgxRjRBNyk=' },
    @{ From='J8OwxbjCpcKQJw=='; To='U3RyaW5nLmZyb21Db2RlUG9pbnQoMHgxRjk1MCk=' },
    @{ From='J8OwxbjCjcK9w6/CuMKPJw=='; To='U3RyaW5nLmZyb21Db2RlUG9pbnQoMHgxRjM3RCwgMHhGRTBGKQ==' },
    @{ From='w7DFuOKAuuKAmQ=='; To='e1N0cmluZy5mcm9tQ29kZVBvaW50KDB4MUY2RDIpfQ==' },
    @{ From='w4LCtw=='; To='IHwg' },
    @{ From='w4PigJQ='; To='eA==' },
    @{ From='w6LigqzCpg=='; To='Li4u' },
    @{ From='w6LigqzigJ0='; To='LQ==' },
    @{ From='w6LigKDigJk='; To='LT4=' },
    @{ From='w6LigKDigJg='; To='Xg==' },
    @{ From='w6LigKDCkA=='; To='Jmx0Oy0=' },
    @{ From='w6LLhuKAmQ=='; To='LQ==' },
    @{ From='w6LFk8Km'; To='Kg==' },
    @{ From='w5nLhg=='; To='V0Q=' },
    @{ From='YWN0aXZlPyfDosWT4oCcJzonKyc='; To='YWN0aXZlP1N0cmluZy5mcm9tQ2hhckNvZGUoMHgyNzEzKTonKyc=' }
)

$totalMatches = 0
$details = @()
foreach ($item in $replacements) {
    $badText = From-B64 $item.From
    $goodText = From-B64 $item.To
    $count = ([regex]::Matches($source, [regex]::Escape($badText))).Count
    if ($count -gt 0) {
        $source = $source.Replace($badText, $goodText)
        $totalMatches += $count
        $details += [PSCustomObject]@{ Count = $count; Replacement = $goodText }
    }
}

if ($totalMatches -eq 0) {
    throw 'Tidak ditemukan pola karakter rusak yang dikenali. File tidak diubah; kemungkinan kode lokal sudah diperbaiki atau berbeda dari versi yang diperiksa.'
}

# Pastikan tidak ada pola kerusakan yang dikenal masih tersisa.
$remainingPatterns = @(
    (From-B64 'J8OwxbjCjeKAlCc='), (From-B64 'J8OwxbjCjeKAuic='), (From-B64 'J8OwxbjCjcWTJw=='),
    (From-B64 'J8OwxbjCp+KAuSc='), (From-B64 'J8OwxbjigJnCpyc='), (From-B64 'J8OwxbjCpcKQJw=='),
    (From-B64 'J8OwxbjCjcK9w6/CuMKPJw=='), (From-B64 'w7DFuOKAuuKAmQ=='), (From-B64 'w4LCtw=='),
    (From-B64 'w4PigJQ='), (From-B64 'w6LigqzCpg=='), (From-B64 'w6LigqzigJ0='),
    (From-B64 'w6LigKDigJk='), (From-B64 'w6LigKDigJg='), (From-B64 'w6LigKDCkA=='),
    (From-B64 'w6LLhuKAmQ=='), (From-B64 'w6LFk8Km'), (From-B64 'w5nLhg=='),
    (From-B64 'YWN0aXZlPyfDosWT4oCcJzonKyc=')
)
foreach ($badText in $remainingPatterns) {
    if ($source.Contains($badText)) {
        throw 'Pemeriksaan akhir menemukan karakter rusak yang belum terganti. File asli tidak ditimpa.'
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$targetPath.bak-karakter-$stamp"
[System.IO.File]::Copy($targetPath, $backupPath, $false)
try {
    [System.IO.File]::WriteAllText($targetPath, $source, $utf8)
    $verify = [System.IO.File]::ReadAllText($targetPath, [System.Text.Encoding]::UTF8)
    if ($verify -ne $source) { throw 'Verifikasi setelah menyimpan gagal.' }
} catch {
    [System.IO.File]::Copy($backupPath, $targetPath, $true)
    throw "Perubahan gagal diverifikasi. File asli dipulihkan dari backup. Detail: $($_.Exception.Message)"
}

Write-Host ''
Write-Host 'Perbaikan karakter berhasil diterapkan.' -ForegroundColor Green
Write-Host "Jumlah penggantian: $totalMatches"
Write-Host "File diperbarui: src\App.jsx"
Write-Host "Backup: $backupPath"
Write-Host 'File lain tidak diubah.'

$ErrorActionPreference = 'Stop'

$target = Join-Path (Get-Location) 'src\App.jsx'
if (-not (Test-Path -LiteralPath $target)) {
    throw "File tidak ditemukan: $target. Jalankan skrip dari folder utama proyek yang berisi package.json."
}

$content = [System.IO.File]::ReadAllText($target)
$original = $content

$replacements = @(
    @{
        Name = 'dekorasi hero'
        Pattern = '<div\s+className="hero-pattern">.*?</div>'
        Replacement = '<div className="hero-pattern">✦</div>'
    },
    @{
        Name = 'label keunggulan hero'
        Pattern = '<div\s+className="hero-meta">.*?</div>'
        Replacement = '<div className="hero-meta"><span>Praktis</span><span>Tertata</span><span>Mudah dikonfirmasi</span></div>'
    },
    @{
        Name = 'logo teks footer'
        Pattern = '<span\s+className="footer-mark">.*?</span>'
        Replacement = '<span className="footer-mark">WD</span>'
    },
    @{
        Name = 'teks dekoratif footer yang rusak'
        Pattern = '<span\s+className="footer-note">.*?</span>'
        Replacement = ''
    }
)

foreach ($item in $replacements) {
    $count = [regex]::Matches($content, $item.Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline).Count
    if ($count -ne 1) {
        throw "Pemeriksaan gagal: bagian '$($item.Name)' ditemukan $count kali (seharusnya tepat 1). Tidak ada file yang diubah."
    }
    $content = [regex]::Replace(
        $content,
        $item.Pattern,
        $item.Replacement,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
}

if ($content -eq $original) {
    throw 'Tidak ada perubahan yang diperlukan. File tidak ditulis.'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$target.bak-tampilan-karakter-$timestamp"
Copy-Item -LiteralPath $target -Destination $backup

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($target, $content, $utf8NoBom)

    $verify = [System.IO.File]::ReadAllText($target)
    $required = @(
        '<div className="hero-pattern">✦</div>',
        '<div className="hero-meta"><span>Praktis</span><span>Tertata</span><span>Mudah dikonfirmasi</span></div>',
        '<span className="footer-mark">WD</span>'
    )
    foreach ($text in $required) {
        if (-not $verify.Contains($text)) { throw "Verifikasi setelah penulisan gagal: $text" }
    }
    if ($verify -match '<span\s+className="footer-note">') {
        throw 'Verifikasi gagal: teks dekoratif footer masih tersisa.'
    }
}
catch {
    Copy-Item -LiteralPath $backup -Destination $target -Force
    throw "Perbaikan gagal dan file asli sudah dipulihkan dari backup. Detail: $($_.Exception.Message)"
}

Write-Host ''
Write-Host 'BERHASIL: tampilan karakter sudah diperbaiki.' -ForegroundColor Green
Write-Host "File diperbarui : $target"
Write-Host "Backup          : $backup"
Write-Host 'Bagian yang diperbaiki: dekorasi hero, label hero, logo teks footer, dan teks footer yang rusak.'

$ErrorActionPreference = "Stop"

$target = Join-Path (Get-Location) "src\App.jsx"
if (-not (Test-Path -LiteralPath $target)) {
    throw "src\App.jsx not found. Run this script from the project root folder."
}

$backup = "$target.bak-tampilan-v2"
Copy-Item -LiteralPath $target -Destination $backup -Force

$content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)

# Build the damaged UTF-8-as-Windows-1252 strings from code points.
# This keeps this PowerShell script itself ASCII-only.
$replacements = @(
    @(([char]0x00F0).ToString() + [char]0x0178 + [char]0x008D + [char]0x2017, [char]::ConvertFromUtf32(0x1F357)),
    @(([char]0x00F0).ToString() + [char]0x0178 + [char]0x008D + [char]0x201B, [char]::ConvertFromUtf32(0x1F35B)),
    @(([char]0x00F0).ToString() + [char]0x0178 + [char]0x008D + [char]0x0153, [char]::ConvertFromUtf32(0x1F35C)),
    @(([char]0x00F0).ToString() + [char]0x0178 + [char]0x00A7 + [char]0x2039, [char]::ConvertFromUtf32(0x1F9CB)),
    @(([char]0x00F0).ToString() + [char]0x0178 + [char]0x2019 + [char]0x00A7, [char]::ConvertFromUtf32(0x1F4A7)),
    @(([char]0x00F0).ToString() + [char]0x0178 + [char]0x00A5 + [char]0x0090, [char]::ConvertFromUtf32(0x1F950)),
    @(([char]0x00F0).ToString() + [char]0x0178 + [char]0x008D + [char]0x00BD + [char]0x00EF + [char]0x00B8 + [char]0x008F, [char]::ConvertFromUtf32(0x1F37D) + [char]::ConvertFromUtf32(0xFE0F)),
    @(([char]0x00F0).ToString() + [char]0x0178 + [char]0x203A + [char]0x2019, [char]::ConvertFromUtf32(0x1F6D2)),
    @(([char]0x00E2).ToString() + [char]0x20AC + [char]0x201D, [char]0x2014),
    @(([char]0x00C2).ToString() + [char]0x00B7, [char]0x00B7),
    @(([char]0x00E2).ToString() + [char]0x20AC + [char]0x00A6, [char]0x2026),
    @(([char]0x00C3).ToString() + [char]0x2014, [char]0x00D7),
    @(([char]0x00E2).ToString() + [char]0x2020 + [char]0x2019, [char]0x2192),
    @(([char]0x00E2).ToString() + [char]0x20AC + [char]0x0153, [char]0x201C),
    @(([char]0x00E2).ToString() + [char]0x20AC + [char]0x009D, [char]0x201D),
    @(([char]0x00E2).ToString() + [char]0x20AC + [char]0x2122, [char]0x2019)
)

$changed = 0
foreach ($pair in $replacements) {
    $before = $content
    $content = $content.Replace([string]$pair[0], [string]$pair[1])
    if ($content -cne $before) { $changed++ }
}

[System.IO.File]::WriteAllText($target, $content, [System.Text.UTF8Encoding]::new($false))

Write-Host "Display text repair completed." -ForegroundColor Green
Write-Host "Replacement patterns applied: $changed"
Write-Host "Backup created: $backup"
Write-Host "Next, run: npm run build"

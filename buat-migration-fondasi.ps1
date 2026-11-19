$ErrorActionPreference = "Stop"

$root = (Get-Location).Path
$sourceFiles = @(
  "warung-darul-ilmi-database-v1.sql",
  "migration-v2-guest-checkout.sql",
  "migration-v3-operations-security.sql",
  "migration-v4-whatsapp-routing.sql",
  "migration-v5-cashier-scope-hardening.sql",
  "warung-darul-ilmi-fix-order-history-trigger.sql"
)

foreach ($relative in $sourceFiles) {
    $full = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $full)) {
        throw "File sumber tidak ditemukan: $relative. Pastikan ZIP diekstrak pada folder utama repo branch app."
    }
}

$v2Path = Join-Path $root "migration-v2-guest-checkout.sql"
$v2Text = [System.IO.File]::ReadAllText($v2Path, [System.Text.Encoding]::UTF8)
if ($v2Text -notmatch "p_access_token\s+text" -or
    $v2Text -notmatch "guest_access_token_hash" -or
    $v2Text -notmatch "extensions\.digest") {
    throw "SQL Guest Checkout v2 belum versi 8 parameter + hash token. Pasang dahulu file migration-v2-guest-checkout.sql dari ZIP Fix Checkout."
}

$requiredMigrations = @(
  "202611180001_secure_store_settings.sql",
  "202611180002_store_brand_logo.sql",
  "202611180003_align_guest_checkout_rpc.sql"
)
$migrationDir = Join-Path $root "supabase\migrations"
if (-not (Test-Path -LiteralPath $migrationDir)) {
    throw "Folder supabase\migrations tidak ditemukan."
}
foreach ($name in $requiredMigrations) {
    if (-not (Test-Path -LiteralPath (Join-Path $migrationDir $name))) {
        throw "Migration lanjutan tidak ditemukan: supabase\migrations\$name"
    }
}

$baselineVersion = "202611170001"
$outputName = "${baselineVersion}_initial_complete_schema.sql"
$outputPath = Join-Path $migrationDir $outputName

if (Test-Path -LiteralPath $outputPath) {
    $backupPath = "$outputPath.bak"
    Copy-Item -LiteralPath $outputPath -Destination $backupPath -Force
    Write-Host "Cadangan migration lama dibuat: $backupPath" -ForegroundColor Yellow
}

$parts = @()
foreach ($relative in $sourceFiles) {
    $full = Join-Path $root $relative
    $content = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)

    # The combined baseline must have one transaction boundary, not nested commits.
    $content = [System.Text.RegularExpressions.Regex]::Replace(
        $content,
        '(?im)^\s*(begin|commit)\s*;\s*$',
        ''
    )

    $parts += "-- ============================================================"
    $parts += "-- Source: $relative"
    $parts += "-- ============================================================"
    $parts += $content.Trim()
    $parts += ""
}

$baseline = @"
-- WARUNG DARUL ILMI: COMPLETE INITIAL DATABASE BASELINE
-- Generated from the checked migration source files on branch app.
-- This file is intended for a NEW Supabase database only.
-- Existing production databases must mark this baseline as already applied
-- in migration history; do NOT execute its SQL over an existing database.
--
-- Included order:
-- 1. Database v1
-- 2. Guest Checkout v2 (8 parameters, SHA-256 token hash)
-- 3. Operations/security v3
-- 4. WhatsApp routing v4
-- 5. Cashier scope hardening v5
-- 6. Order history trigger correction
--
-- Supabase provides the "extensions" schema. Ensure pgcrypto is available
-- there because the checkout RPC uses extensions.digest().

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

begin;

$($parts -join "`r`n")

commit;
"@

[System.IO.File]::WriteAllText(
    $outputPath,
    $baseline,
    [System.Text.UTF8Encoding]::new($false)
)

# Basic structural checks on the generated migration.
$generated = [System.IO.File]::ReadAllText($outputPath, [System.Text.Encoding]::UTF8)
foreach ($needle in @(
    "create table public.store_settings",
    "create table public.orders",
    "create or replace function public.create_guest_order",
    "p_access_token text",
    "guest_access_token_hash",
    "public.can_access_order_gender",
    "whatsapp_number_putra",
    "log_order_status_after_change"
)) {
    if (-not $generated.Contains($needle)) {
        throw "Pemeriksaan hasil gagal: elemen tidak ditemukan: $needle"
    }
}

Write-Host ""
Write-Host "Migration fondasi berhasil dibuat:" -ForegroundColor Green
Write-Host $outputPath -ForegroundColor Green
Write-Host ""
Write-Host "Urutan migration sekarang:"
Get-ChildItem -LiteralPath $migrationDir -Filter "*.sql" |
    Sort-Object Name |
    ForEach-Object { Write-Host (" - " + $_.Name) }
Write-Host ""
Write-Host "Skrip hanya membuat file SQL lokal. Tidak ada perintah SQL yang dikirim ke Supabase."

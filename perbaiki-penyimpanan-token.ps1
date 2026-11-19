$ErrorActionPreference = "Stop"

$target = Join-Path (Get-Location) "src\App.jsx"
if (-not (Test-Path -LiteralPath $target)) {
    throw "src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek."
}

$content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)

$oldBlock = @'
    // Keep the bearer token on this device so a future guest-order lookup can use it.
    try {
      const tokenStoreKey = 'wdi_guest_order_tokens';
      const savedTokens = JSON.parse(localStorage.getItem(tokenStoreKey) || '[]');
      savedTokens.push({order_id:result.order_id,order_number:result.order_number,access_token:accessToken,created_at:new Date().toISOString()});
      localStorage.setItem(tokenStoreKey, JSON.stringify(savedTokens.slice(-50)));
    } catch (storageError) {
      console.warn('Token pesanan tidak dapat disimpan di perangkat ini.', storageError);
    }
'@.TrimEnd("`r","`n")

$occurrences = ([regex]::Matches($content, [regex]::Escape($oldBlock))).Count
if ($occurrences -ne 1) {
    throw "Blok penyimpanan token ditemukan $occurrences kali (harus tepat 1). Tidak ada perubahan diterapkan."
}

$updated = $content.Replace($oldBlock, "")

if ($updated.Contains("wdi_guest_order_tokens")) {
    throw "Nama penyimpanan token masih ditemukan setelah perubahan. Tidak ada file yang ditulis."
}
if ($updated -notmatch "p_access_token\s*:\s*accessToken") {
    throw "Token tidak lagi dikirim ke RPC. Tidak ada file yang ditulis."
}
if ($updated -notmatch "crypto\?\.getRandomValues") {
    throw "Pembuatan token acak aman tidak ditemukan. Tidak ada file yang ditulis."
}

$backup = "$target.bak-sebelum-fix-token-storage"
Copy-Item -LiteralPath $target -Destination $backup -Force

[System.IO.File]::WriteAllText(
    $target,
    $updated,
    [System.Text.UTF8Encoding]::new($false)
)

# Read-back and final checks.
$check = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
if ($check.Contains("wdi_guest_order_tokens") -or
    $check -notmatch "p_access_token\s*:\s*accessToken") {
    Copy-Item -LiteralPath $backup -Destination $target -Force
    throw "Validasi setelah penulisan gagal. File asli dipulihkan dari backup."
}

Write-Host ""
Write-Host "BERHASIL: penyimpanan token mentah di localStorage dihapus." -ForegroundColor Green
Write-Host "Token tetap dibuat dengan crypto.getRandomValues dan dikirim ke RPC satu kali."
Write-Host "Cadangan asli: $backup"
Write-Host ""
Write-Host "Berikutnya jalankan: npm run build"

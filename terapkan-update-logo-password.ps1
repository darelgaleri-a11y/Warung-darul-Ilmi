$ErrorActionPreference = "Stop"

$target = Join-Path (Get-Location) "src\App.jsx"
if (-not (Test-Path -LiteralPath $target)) {
    throw "src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek."
}

$backup = "$target.bak-logo-password"
Copy-Item -LiteralPath $target -Destination $backup -Force
$content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)

function Replace-Once([string]$source, [string]$old, [string]$new, [string]$label) {
    $count = ([regex]::Matches($source, [regex]::Escape($old))).Count
    if ($count -ne 1) { throw "Pola '$label' ditemukan $count kali (harus tepat 1). Pemrosesan dihentikan." }
    return $source.Replace($old, $new)
}

$content = Replace-Once $content `
"const [storeSettings, setStoreSettings] = useState({ store_name: 'Warung Darul Ilmi', whatsapp_number: '', whatsapp_number_putra: '', whatsapp_number_putri: '', bank_name: '', bank_account_number: '', bank_account_name: '' });" `
"const [storeSettings, setStoreSettings] = useState({ store_name: 'Warung Darul Ilmi', brand_logo_url: '', whatsapp_number: '', whatsapp_number_putra: '', whatsapp_number_putri: '', bank_name: '', bank_account_number: '', bank_account_name: '' });" `
"store settings state"

$content = Replace-Once $content `
"          store_name: storeSettings.store_name," `
"          store_name: storeSettings.store_name,
          brand_logo_url: storeSettings.brand_logo_url || null," `
"settings payload"

$content = Replace-Once $content `
"<span className=\"brand-mark\">Ùˆ</span><span><strong>Warung Darul Ilmi</strong><small>Pesan mudah, berkah insyaallah</small></span>" `
"{storeSettings.brand_logo_url ? <img className=\"brand-logo-image\" src={storeSettings.brand_logo_url} alt=\"Logo Warung Darul Ilmi\" onError={e=>{e.currentTarget.style.display='none';}}/> : <span className=\"brand-mark\">و</span>}<span><strong>{storeSettings.store_name || 'Warung Darul Ilmi'}</strong><small>Pesan mudah, berkah insyaallah</small></span>" `
"header brand"

$content = Replace-Once $content `
"<label>Nama warung<input value={storeSettings.store_name||''} onChange={e=>setStoreSettings({...storeSettings,store_name:e.target.value})}/></label>" `
"<label>Nama warung<input value={storeSettings.store_name||''} onChange={e=>setStoreSettings({...storeSettings,store_name:e.target.value})}/></label><label>URL logo warung<input type=\"url\" value={storeSettings.brand_logo_url||''} onChange={e=>setStoreSettings({...storeSettings,brand_logo_url:e.target.value})} placeholder=\"https://.../logo.png\"/><small className=\"muted\">Masukkan URL gambar logo (PNG, JPG, atau WebP). Kosongkan untuk memakai logo teks.</small></label>" `
"logo settings field"

$content = Replace-Once $content `
"<div className=\"password-confirm-panel\"><strong>Verifikasi keamanan perubahan</strong><p className=\"fine-print\">Masukkan password akun Super Admin yang sedang login setiap kali menyimpan pengaturan. Password hanya digunakan untuk verifikasi dan tidak disimpan.</p><label>Password Super Admin<input type=\"password\"" `
"<div className=\"password-confirm-panel\"><label>Password<input type=\"password\"" `
"password description and label"

$css = Join-Path (Get-Location) "src\styles.css"
if (-not (Test-Path -LiteralPath $css)) { throw "src\styles.css tidak ditemukan." }
$cssBackup = "$css.bak-logo-password"
Copy-Item -LiteralPath $css -Destination $cssBackup -Force
$cssText = [System.IO.File]::ReadAllText($css, [System.Text.Encoding]::UTF8)
if (-not $cssText.Contains(".brand-logo-image")) {
    $cssText += "`n`n/* Replaceable store logo */`n.brand-logo-image{width:42px;height:42px;object-fit:contain;flex:0 0 42px;border-radius:10px;background:#fff;padding:3px}`n"
}

[System.IO.File]::WriteAllText($target, $content, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($css, $cssText, [System.Text.UTF8Encoding]::new($false))

Write-Host "Perubahan antarmuka selesai." -ForegroundColor Green
Write-Host "Cadangan App.jsx: $backup"
Write-Host "Cadangan styles.css: $cssBackup"
Write-Host "Berikutnya jalankan: npm run build"

$ErrorActionPreference = "Stop"

function Replace-LiteralOnce([string]$source, [string]$old, [string]$new, [string]$label) {
    $count = ([regex]::Matches($source, [regex]::Escape($old))).Count
    if ($count -ne 1) {
        throw "Pola '$label' ditemukan $count kali; harus tepat satu. File tidak diubah."
    }
    return $source.Replace($old, $new)
}

function Replace-RegexOnce([string]$source, [string]$pattern, [string]$replacement, [string]$label) {
    $matches = [regex]::Matches($source, $pattern)
    if ($matches.Count -ne 1) {
        throw "Pola '$label' ditemukan $($matches.Count) kali; harus tepat satu. File tidak diubah."
    }
    return $source.Replace($matches[0].Value, $replacement)
}

$root = Get-Location
$appPath = Join-Path $root "src\App.jsx"
$cssPath = Join-Path $root "src\styles.css"
if (-not (Test-Path $appPath)) { throw "src\App.jsx tidak ditemukan. Jalankan dari folder utama proyek." }
if (-not (Test-Path $cssPath)) { throw "src\styles.css tidak ditemukan. Jalankan dari folder utama proyek." }

$app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)
$css = [System.IO.File]::ReadAllText($cssPath, [System.Text.Encoding]::UTF8)

$oldState = "  const [storeSettings, setStoreSettings] = useState({ store_name: 'Warung Darul Ilmi', whatsapp_number: '', whatsapp_number_putra: '', whatsapp_number_putri: '', bank_name: '', bank_account_number: '', bank_account_name: '' });"
$newState = "  const [storeSettings, setStoreSettings] = useState({ store_name: 'Warung Darul Ilmi', brand_logo_url: '', whatsapp_number: '', whatsapp_number_putra: '', whatsapp_number_putri: '', bank_name: '', bank_account_number: '', bank_account_name: '' });"
$app = Replace-LiteralOnce $app $oldState $newState "store settings state"

$oldPasswordState = "  const [settingsPassword, setSettingsPassword] = useState('');"
$newPasswordState = @'
  const [settingsPassword, setSettingsPassword] = useState('');
  const [brandLogoFile, setBrandLogoFile] = useState(null);
  const [removeBrandLogo, setRemoveBrandLogo] = useState(false);
'@.TrimEnd("`r","`n")
$app = Replace-LiteralOnce $app $oldPasswordState $newPasswordState "logo upload state"

$headerPattern = '(?s)<header className="topbar"><button className="brand" onClick=\{\(\)=>setPage\(''order''\)\} aria-label="Ke halaman pemesanan">.*?</button>\s*<nav className="nav">'
$newHeader = '<header className="topbar"><button className="brand" onClick={()=>setPage(''order'')} aria-label="Ke halaman pemesanan">{storeSettings.brand_logo_url ? <img className="brand-logo-image" src={storeSettings.brand_logo_url} alt="Logo toko" /> : <span className="brand-mark">WD</span>}<span><strong>{storeSettings.store_name || ''Warung Darul Ilmi''}</strong><small>Pesan mudah, berkah insyaallah</small></span></button><nav className="nav">'
$app = Replace-RegexOnce $app $headerPattern $newHeader "header logo"

$savePattern = '(?s)async function saveSettings\(e\) \{.*?\n  \}\n  async function loadDateOverrides\(\)'
$newSave = @'
async function saveSettings(e) {
    e.preventDefault();
    if (!settingsPassword) { setNotice('Masukkan password untuk mengonfirmasi perubahan pengaturan.'); return; }
    setSettingsBusy(true);
    const { error } = await supabase.functions.invoke('update-store-settings', {
      body: {
        password: settingsPassword,
        settings: {
          store_name: storeSettings.store_name,
          whatsapp_number: storeSettings.whatsapp_number,
          whatsapp_number_putra: storeSettings.whatsapp_number_putra,
          whatsapp_number_putri: storeSettings.whatsapp_number_putri,
          bank_name: storeSettings.bank_name,
          bank_account_number: storeSettings.bank_account_number,
          bank_account_name: storeSettings.bank_account_name,
          payment_instructions: storeSettings.payment_instructions
        },
        logo: brandLogoFile ? { contentType: brandLogoFile.contentType, base64: brandLogoFile.base64 } : null,
        removeLogo: removeBrandLogo
      }
    });
    setSettingsBusy(false);
    setSettingsPassword('');
    if (!error) {
      const { data: refreshedSettings } = await supabase.from('store_settings').select('*').eq('id', true).maybeSingle();
      if (refreshedSettings) setStoreSettings(current => ({ ...current, ...refreshedSettings }));
      setBrandLogoFile(null);
      setRemoveBrandLogo(false);
    }
    setNotice(error ? `Pengaturan gagal disimpan: ${error.message}` : 'Pengaturan toko dan logo berhasil disimpan setelah verifikasi password.');
  }
  async function loadDateOverrides()
'@.TrimEnd("`r","`n")
$app = Replace-RegexOnce $app $savePattern $newSave "saveSettings function"

$oldStoreLabel = @'
<label>Nama warung<input value={storeSettings.store_name||''} onChange={e=>setStoreSettings({...storeSettings,store_name:e.target.value})}/></label>
'@.Trim()
$newStoreLabel = @'
<label>Nama warung<input value={storeSettings.store_name||''} onChange={e=>setStoreSettings({...storeSettings,store_name:e.target.value})}/></label>
          <div className="settings-logo-field">
            <label>Logo toko (PNG, JPG, atau WebP)
              <input type="file" accept="image/png,image/jpeg,image/webp" onChange={e=>{const file=e.target.files?.[0];if(!file)return;if(file.size>2*1024*1024){setNotice('Ukuran logo maksimal 2 MB.');e.target.value='';return;}if(!['image/png','image/jpeg','image/webp'].includes(file.type)){setNotice('Format logo harus PNG, JPG, atau WebP.');e.target.value='';return;}const reader=new FileReader();reader.onload=()=>{const dataUrl=String(reader.result||'');const base64=dataUrl.split(',')[1]||'';if(base64)setBrandLogoFile({contentType:file.type,base64,previewUrl:dataUrl});};reader.onerror=()=>setNotice('Gagal membaca file logo.');reader.readAsDataURL(file);setRemoveBrandLogo(false);}}/>
            </label>
            {(brandLogoFile?.previewUrl || (!removeBrandLogo && storeSettings.brand_logo_url)) && <div className="store-logo-preview"><img src={brandLogoFile?.previewUrl || storeSettings.brand_logo_url} alt="Pratinjau logo toko"/><button type="button" onClick={()=>{setBrandLogoFile(null);setRemoveBrandLogo(true);}}>Gunakan logo bawaan</button></div>}
            {!brandLogoFile && !storeSettings.brand_logo_url && !removeBrandLogo && <p className="muted">Belum ada logo khusus. Logo bawaan akan ditampilkan.</p>}
            {removeBrandLogo && <p className="muted">Logo khusus akan dihapus setelah pengaturan disimpan.</p>}
          </div>
'@.Trim()
$app = Replace-LiteralOnce $app $oldStoreLabel $newStoreLabel "logo upload field"

$passwordPattern = '(?s)<div className="password-confirm-panel">.*?</div>'
$newPasswordPanel = '<div className="password-confirm-panel"><label>Password<input type="password" name="settings-password-confirmation-entry" autoComplete="new-password" readOnly onFocus={e=>e.currentTarget.removeAttribute("readonly")} value={settingsPassword} onChange={e=>setSettingsPassword(e.target.value)} required/></label></div>'
$app = Replace-RegexOnce $app $passwordPattern $newPasswordPanel "password panel"

$app = [regex]::Replace($app, '(<div className="brand-mark">)[^<]*(</div>)', '$1WD$2')

if (-not $css.Contains(".brand-logo-image")) {
    $css += @'

/* Store logo upload and header image */
.brand-logo-image{width:42px;height:42px;flex:0 0 42px;object-fit:contain;border-radius:10px;background:#fff;padding:3px}
.settings-logo-field{display:grid;gap:10px;padding:14px;border:1px solid #e9e4d7;border-radius:12px;background:#fbfaf5}
.settings-logo-field input[type=file]{height:auto;min-height:44px;padding:8px;background:#fff}
.store-logo-preview{display:flex;align-items:center;gap:12px;flex-wrap:wrap}
.store-logo-preview img{width:76px;height:76px;object-fit:contain;background:#fff;border:1px solid #e9e4d7;border-radius:12px;padding:6px}
.store-logo-preview button{min-height:38px;border:1px solid #ddd8c9;background:#f8f6ef;color:#244738;border-radius:8px;padding:8px 12px;font:700 11px 'DM Sans';cursor:pointer}
'@
}

$appBackup = "$appPath.bak-logo-password-upload"
$cssBackup = "$cssPath.bak-logo-password-upload"
Copy-Item $appPath $appBackup -Force
Copy-Item $cssPath $cssBackup -Force
[System.IO.File]::WriteAllText($appPath, $app, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($cssPath, $css, [System.Text.UTF8Encoding]::new($false))

Write-Host "Perubahan App.jsx dan styles.css berhasil diterapkan." -ForegroundColor Green
Write-Host "Cadangan: $appBackup"
Write-Host "Cadangan: $cssBackup"
Write-Host "Selanjutnya jalankan: npm run build"

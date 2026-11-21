$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appPath = Join-Path $root 'src\App.jsx'
if (!(Test-Path $appPath)) {
  throw 'src\App.jsx tidak ditemukan. Ekstrak ZIP di folder utama repository (folder yang berisi package.json).'
}

$app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8).Replace("`r`n","`n")

function Replace-Once {
  param([string]$Text,[string]$Old,[string]$New,[string]$Label)
  $first=$Text.IndexOf($Old,[System.StringComparison]::Ordinal)
  if($first -lt 0){throw "Bagian '$Label' tidak ditemukan. File tidak diubah."}
  $second=$Text.IndexOf($Old,$first+$Old.Length,[System.StringComparison]::Ordinal)
  if($second -ge 0){throw "Bagian '$Label' muncul lebih dari sekali. File tidak diubah."}
  return $Text.Substring(0,$first)+$New+$Text.Substring($first+$Old.Length)
}

# Helpers for creating an Android WhatsApp intent URL with an explicit web fallback.
$oldHelper=@'
function normalizeGender(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'putra') return 'Putra';
  if (normalized === 'putri') return 'Putri';
  return '';
}
'@
$newHelper=@'
function normalizeGender(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'putra') return 'Putra';
  if (normalized === 'putri') return 'Putri';
  return '';
}
function buildWhatsAppUrls(phone, message) {
  const normalizedPhone = String(phone || '').replace(/\D/g, '');
  const encodedMessage = encodeURIComponent(String(message || ''));
  if (!normalizedPhone) return { appUrl: '', webUrl: '' };
  return {
    // Android resolves this intent to the installed WhatsApp package when available.
    appUrl: `intent://send/?phone=${normalizedPhone}&text=${encodedMessage}#Intent;scheme=whatsapp;package=com.whatsapp;end`,
    webUrl: `https://wa.me/${normalizedPhone}?text=${encodedMessage}`
  };
}
'@
$app=Replace-Once $app $oldHelper $newHelper 'helper build URL WhatsApp'

# Keep the reserved tab approach to avoid popup blockers after the async order RPC.
# On Android navigate that tab to the package-targeted intent; web URL is a deliberate fallback.
$oldBlock=@'
      const whatsappUrl = wa ? `https://wa.me/${wa}?text=${encodeURIComponent(message)}` : '';
      if (whatsappUrl) {
        setWhatsAppFallbackUrl(whatsappUrl);
        if (whatsappTab && !whatsappTab.closed) {
          try {
            whatsappTab.location.replace(whatsappUrl);
          } catch (navigationError) {
            try { whatsappTab.close(); } catch (closeError) { /* no-op */ }
          }
        }
      } else if (whatsappTab && !whatsappTab.closed) {
        whatsappTab.close();
      }
'@
$newBlock=@'
      const { appUrl: whatsappAppUrl, webUrl: whatsappWebUrl } = buildWhatsAppUrls(wa, message);
      if (whatsappWebUrl) {
        // Keep the fallback available when Android/browser refuses the app intent.
        setWhatsAppFallbackUrl(whatsappWebUrl);
        if (whatsappTab && !whatsappTab.closed) {
          try {
            const isAndroid = /Android/i.test(navigator.userAgent || '');
            whatsappTab.location.replace(isAndroid ? whatsappAppUrl : whatsappWebUrl);
          } catch (navigationError) {
            try { whatsappTab.close(); } catch (closeError) { /* no-op */ }
          }
        }
      } else if (whatsappTab && !whatsappTab.closed) {
        whatsappTab.close();
      }
'@
$app=Replace-Once $app $oldBlock $newBlock 'pengalihan WhatsApp selepas pesanan tersimpan'

# Make the fallback action say explicitly that this is the browser/web route.
$oldButton=@'
<button className="primary full" type="button" onClick={()=>window.open(whatsAppFallbackUrl,'_blank','noopener,noreferrer')}>Buka WhatsApp untuk mengirim pesanan</button>
'@
$newButton=@'
<button className="primary full" type="button" onClick={()=>window.open(whatsAppFallbackUrl,'_blank','noopener,noreferrer')}>Buka WhatsApp melalui browser (alternatif)</button>
'@
$app=Replace-Once $app $oldButton $newButton 'label tombol fallback WhatsApp'

# Validate new URL construction and ensure order RPC and message are untouched.
if(!$app.Contains('package=com.whatsapp') -or !$app.Contains('https://wa.me/${normalizedPhone}?text=${encodedMessage}')) {
  throw 'Validasi URL WhatsApp gagal. File tidak diubah.'
}
if(!$app.Contains("supabase.rpc('create_guest_order'")) {
  throw 'Validasi proses simpan order gagal. File tidak diubah.'
}

$backup="$appPath.before-whatsapp-android-fix"
Copy-Item $appPath $backup -Force
$utf8=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($appPath,$app,$utf8)

Write-Host ''
Write-Host 'Perbaikan alur WhatsApp Android berhasil diterapkan.' -ForegroundColor Green
Write-Host "Backup: $backup"
Write-Host 'Lanjutkan dengan npm run build, lalu npm run dev.'

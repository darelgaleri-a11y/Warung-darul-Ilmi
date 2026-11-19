$ErrorActionPreference = 'Stop'

$projectRoot = Get-Location
$appPath = Join-Path $projectRoot 'src\App.jsx'
if (-not (Test-Path $appPath)) {
    throw 'File src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek branch app.'
}

$source = [System.IO.File]::ReadAllText($appPath)
$newline = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
$text = $source.Replace("`r`n", "`n")

if ($text.Contains('whatsAppFallbackUrl') -or $text.Contains('orderSubmitting')) {
    throw 'Perbaikan checkout WhatsApp tampaknya sudah pernah diterapkan. Tidak ada file yang diubah.'
}

$stateAnchor = "  const [loadingOrders, setLoadingOrders] = useState(false);"
if (([regex]::Matches($text, [regex]::Escape($stateAnchor))).Count -ne 1) {
    throw 'Titik penambahan state tidak cocok dengan App.jsx. Pastikan menggunakan kode terbaru dari branch app.'
}
$text = $text.Replace($stateAnchor, $stateAnchor + "`n  const [orderSubmitting, setOrderSubmitting] = useState(false);`n  const [whatsAppFallbackUrl, setWhatsAppFallbackUrl] = useState('');")

$functionStart = $text.IndexOf('  async function placeOrder() {')
$functionEnd = $text.IndexOf("`n  async function updateOrder", $functionStart)
if ($functionStart -lt 0 -or $functionEnd -lt 0) {
    throw 'Fungsi placeOrder() atau batas updateOrder() tidak ditemukan. File tidak diubah.'
}
if (($text.IndexOf('  async function placeOrder() {', $functionStart + 1)) -ge 0) {
    throw 'Ditemukan lebih dari satu fungsi placeOrder(). File tidak diubah.'
}

$newFunction = @'
  async function placeOrder() {
    if (orderSubmitting) return;
    if (!supabase || databaseStatus !== 'connected') { setNotice('Database belum tersambung. Pesanan belum dikirim. Periksa konfigurasi Supabase.'); return; }
    if (!identity.name.trim() || !identity.dorm || !identity.className) { setNotice('Lengkapi nama, asrama, dan kelas.'); return; }
    if (!cart.length) { setNotice('Keranjang masih kosong.'); return; }

    const selectedWhatsApp = identity.gender === 'Putri'
      ? (storeSettings.whatsapp_number_putri || storeSettings.whatsapp_number)
      : (storeSettings.whatsapp_number_putra || storeSettings.whatsapp_number);
    const wa = (selectedWhatsApp || '').replace(/\D/g, '');

    // Reserve a browser tab during the original click, before awaiting the database.
    // A visible fallback action is also rendered after success if the browser blocks it.
    let whatsappTab = null;
    if (wa) {
      try {
        whatsappTab = window.open('about:blank', '_blank');
        if (whatsappTab) {
          whatsappTab.opener = null;
          whatsappTab.document.title = 'Menyiapkan WhatsApp';
          whatsappTab.document.body.textContent = 'Pesanan sedang disimpan. WhatsApp akan dibuka setelah penyimpanan selesai.';
        }
      } catch (popupError) {
        whatsappTab = null;
      }
    }

    setOrderSubmitting(true);
    setWhatsAppFallbackUrl('');
    try {
      const payload = cart.map(x => ({ product_id: Number(x.id), quantity: x.qty }));
      // The database requires a 256-bit random guest access token (64 hex characters).
      if (!globalThis.crypto?.getRandomValues) {
        if (whatsappTab && !whatsappTab.closed) whatsappTab.close();
        setNotice('Browser tidak mendukung pembuatan token pesanan yang aman. Gunakan browser terbaru melalui HTTPS.');
        return;
      }
      const tokenBytes = new Uint8Array(32);
      globalThis.crypto.getRandomValues(tokenBytes);
      const accessToken = Array.from(tokenBytes, byte => byte.toString(16).padStart(2, '0')).join('');
      const { data, error } = await supabase.rpc('create_guest_order', {
        p_guest_name: identity.name.trim(), p_guest_gender: identity.gender, p_guest_dormitory: identity.dorm, p_guest_class: identity.className,
        p_guest_phone: identity.phone.trim() || null, p_customer_note: identity.note.trim() || null, p_items: payload, p_access_token: accessToken
      });
      if (error) {
        if (whatsappTab && !whatsappTab.closed) whatsappTab.close();
        setNotice(`Pesanan gagal disimpan: ${error.message}. Keranjang tetap disimpan; bila terjadi gangguan koneksi, periksa antrean kasir sebelum mencoba lagi.`);
        return;
      }

      const result = Array.isArray(data) ? data[0] : data;
      const validResult = result && result.order_id && result.order_number && result.delivery_date && Number.isFinite(Number(result.total_amount));
      if (!validResult) {
        if (whatsappTab && !whatsappTab.closed) whatsappTab.close();
        setNotice('Server tidak mengembalikan detail nomor pesanan yang lengkap. Pesanan mungkin sudah tersimpan. Jangan langsung mengirim ulang; periksa antrean kasir atau hubungi admin terlebih dahulu.');
        return;
      }

      const items = cart.map(x => ({ ...x }));
      const message = [
        `*${storeSettings.store_name || 'WARUNG DARUL ILMI'}*`,
        `Nomor: ${result.order_number}`,
        `Nama: ${identity.name}`,
        `Kategori: ${identity.gender}`,
        `Asrama: ${identity.dorm}`,
        `Kelas: ${identity.className}`,
        `Tanggal pengiriman: ${new Date(`${result.delivery_date}T00:00:00`).toLocaleDateString('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}`,
        '',
        '*Rincian pesanan:*',
        ...items.map(x => `- ${x.name} x${x.qty} = ${money(x.price * x.qty)}`),
        `*Total: ${money(result.total_amount)}*`,
        storeSettings.bank_name ? `Bank: ${storeSettings.bank_name}` : '',
        storeSettings.bank_account_number ? `Rekening: ${storeSettings.bank_account_number}` : '',
        storeSettings.bank_account_name ? `Atas nama: ${storeSettings.bank_account_name}` : '',
        identity.note ? `Catatan: ${identity.note}` : '',
        storeSettings.payment_instructions || 'Mohon konfirmasi pembayaran. Barang diserahkan setelah pembayaran diverifikasi.',
        'Silakan kirim bukti transfer berupa foto/screenshot langsung di chat WhatsApp ini. Bukti transfer tidak diunggah ke aplikasi.'
      ].filter(Boolean).join('\n');

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

      // Clear the cart only after the RPC returned a valid order receipt.
      setCart([]);
      setCartOpen(false);
      setIdentity({ name: '', gender: identity.gender, dorm: '', className: '', phone: '', note: '' });
      if (whatsappUrl) {
        setNotice(`Pesanan ${result.order_number} tersimpan. Tekan tombol Kirim di WhatsApp untuk mengirim konfirmasi. Jika WhatsApp tidak terbuka, gunakan tombol WhatsApp pada halaman ini.`);
      } else {
        setNotice(`Pesanan ${result.order_number} tersimpan online. Admin belum mengisi nomor WhatsApp pada Pengaturan. Hubungi admin dan jangan mengirim ulang pesanan.`);
      }
    } catch (error) {
      if (whatsappTab && !whatsappTab.closed) {
        try { whatsappTab.close(); } catch (closeError) { /* no-op */ }
      }
      setNotice(`Terjadi gangguan saat memproses pesanan: ${error?.message || 'Kesalahan jaringan.'}. Status penyimpanan mungkin belum dapat dipastikan. Periksa antrean kasir sebelum mencoba lagi agar tidak membuat pesanan ganda.`);
    } finally {
      setOrderSubmitting(false);
    }
  }
'@

$text = $text.Substring(0, $functionStart) + $newFunction + $text.Substring($functionEnd)

$noticeAnchor = @'
{notice&&<div className="notice notice-toast" role="status"><span>{notice}</span><button onClick={()=>setNotice('')} aria-label="Tutup pemberitahuan">×</button></div>}
'@
$noticeAnchor = $noticeAnchor.Trim()
if (([regex]::Matches($text, [regex]::Escape($noticeAnchor))).Count -ne 1) {
    throw 'Area pemberitahuan tidak cocok dengan App.jsx. File tidak diubah.'
}
$fallbackUi = @'
{whatsAppFallbackUrl&&<div className="panel" role="status"><strong>Pesanan sudah tersimpan.</strong><p className="fine-print">Jika tab WhatsApp tidak terbuka otomatis, tekan tombol berikut. WhatsApp akan menampilkan pesan yang sudah disiapkan; Anda tetap perlu menekan Kirim di WhatsApp.</p><button className="primary full" type="button" onClick={()=>window.open(whatsAppFallbackUrl,'_blank','noopener,noreferrer')}>Buka WhatsApp untuk mengirim pesanan</button><button type="button" onClick={()=>setWhatsAppFallbackUrl('')}>Tutup pemberitahuan WhatsApp</button></div>}
'@
$text = $text.Replace($noticeAnchor, $noticeAnchor + $fallbackUi)

$oldButton = '<button className="primary full" onClick={placeOrder}>Simpan pesanan & lanjut WhatsApp <span>→</span></button>'
$newButton = @'
<button className="primary full" onClick={placeOrder} disabled={orderSubmitting}>{orderSubmitting?'Menyimpan pesanan…':'Simpan pesanan & lanjut WhatsApp'} <span>→</span></button>
'@
$newButton = $newButton.Trim()
$buttonCount = ([regex]::Matches($text, [regex]::Escape($oldButton))).Count
if ($buttonCount -ne 2) {
    throw "Tombol checkout ditemukan $buttonCount, seharusnya 2 (desktop dan mobile). File tidak diubah."
}
$text = $text.Replace($oldButton, $newButton)

if (-not $text.Contains("window.open('about:blank', '_blank')") -or -not $text.Contains('setWhatsAppFallbackUrl(whatsappUrl)') -or -not $text.Contains('disabled={orderSubmitting}')) {
    throw 'Validasi hasil perubahan gagal. File asli belum ditimpa.'
}

$backupPath = "$appPath.bak-sebelum-fix-checkout-whatsapp"
if (Test-Path $backupPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$appPath.bak-sebelum-fix-checkout-whatsapp-$stamp"
}
Copy-Item -LiteralPath $appPath -Destination $backupPath
$output = $text.Replace("`n", $newline)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($appPath, $output, $utf8NoBom)

$check = [System.IO.File]::ReadAllText($appPath)
if (-not $check.Contains('setWhatsAppFallbackUrl(whatsappUrl)') -or -not $check.Contains('validResult')) {
    Copy-Item -LiteralPath $backupPath -Destination $appPath -Force
    throw 'Pemeriksaan akhir gagal. App.jsx dikembalikan dari cadangan.'
}

Write-Host 'Perbaikan checkout WhatsApp selesai.' -ForegroundColor Green
Write-Host "File diperbarui: $appPath"
Write-Host "Cadangan: $backupPath"
Write-Host 'Jalankan npm run build untuk memeriksa hasilnya.'

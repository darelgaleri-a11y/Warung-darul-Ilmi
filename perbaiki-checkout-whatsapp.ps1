$ErrorActionPreference = 'Stop'

$projectRoot = Get-Location
$appPath = Join-Path $projectRoot 'src\App.jsx'
if (-not (Test-Path $appPath)) {
    throw 'File src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek branch app.'
}

$content = Get-Content -LiteralPath $appPath -Raw -Encoding UTF8
$original = $content

$stateMarker = "  const [notice, setNotice] = useState('');"
if (($content.Split([string]$stateMarker).Count - 1) -ne 1) {
    throw 'Penanda state notice tidak ditemukan tepat satu kali. File mungkin berbeda dari versi yang diaudit; tidak ada perubahan dilakukan.'
}
if ($content.Contains('const [whatsappFallbackUrl, setWhatsappFallbackUrl]')) {
    throw 'Perbaikan checkout WhatsApp tampaknya sudah pernah diterapkan.'
}
$content = $content.Replace($stateMarker, $stateMarker + "`r`n  const [whatsappFallbackUrl, setWhatsappFallbackUrl] = useState('');`r`n  const [orderSubmitting, setOrderSubmitting] = useState(false);")

$startMarker = '  async function placeOrder() {'
$endMarker = '  async function updateOrder(id,patch) {'
$startIndex = $content.IndexOf($startMarker)
$endIndex = $content.IndexOf($endMarker)
if ($startIndex -lt 0 -or $endIndex -le $startIndex) {
    throw 'Blok placeOrder tidak ditemukan seperti yang diharapkan. Tidak ada perubahan dilakukan.'
}

$newFunction = @'
  async function placeOrder() {
    if (orderSubmitting) return;
    if (!supabase || databaseStatus !== 'connected') { setNotice('Database belum tersambung. Pesanan belum dikirim. Periksa konfigurasi Supabase.'); return; }
    if (!identity.name.trim() || !identity.dorm || !identity.className) { setNotice('Lengkapi nama, asrama, dan kelas.'); return; }
    if (!cart.length) { setNotice('Keranjang masih kosong.'); return; }
    if (!globalThis.crypto?.getRandomValues) { setNotice('Browser tidak mendukung pembuatan token pesanan yang aman. Gunakan browser terbaru melalui HTTPS.'); return; }

    const selectedWhatsApp = identity.gender === 'Putri'
      ? (storeSettings.whatsapp_number_putri || storeSettings.whatsapp_number)
      : (storeSettings.whatsapp_number_putra || storeSettings.whatsapp_number);
    const whatsappNumber = (selectedWhatsApp || '').replace(/\D/g, '');

    // Open the destination synchronously during the user's click, before awaiting Supabase.
    // This avoids most browser popup blockers that reject window.open after an async request.
    const whatsappPopup = whatsappNumber ? window.open('about:blank', '_blank') : null;
    if (whatsappPopup) {
      try {
        whatsappPopup.document.title = 'Menyiapkan WhatsApp';
        whatsappPopup.document.body.textContent = 'Pesanan sedang disimpan. Halaman ini akan membuka WhatsApp setelah berhasil.';
      } catch (_) { /* The popup may already have navigated; continue with the fallback link. */ }
    }

    setOrderSubmitting(true);
    setWhatsappFallbackUrl('');
    const payload = cart.map(x => ({ product_id: Number(x.id), quantity: x.qty }));
    const items = cart.map(x => ({ ...x }));
    const customer = { ...identity };

    try {
      const tokenBytes = new Uint8Array(32);
      globalThis.crypto.getRandomValues(tokenBytes);
      const accessToken = Array.from(tokenBytes, byte => byte.toString(16).padStart(2, '0')).join('');
      const { data, error } = await supabase.rpc('create_guest_order', {
        p_guest_name: customer.name.trim(),
        p_guest_gender: customer.gender,
        p_guest_dormitory: customer.dorm,
        p_guest_class: customer.className,
        p_guest_phone: customer.phone.trim() || null,
        p_customer_note: customer.note.trim() || null,
        p_items: payload,
        p_access_token: accessToken
      });
      if (error) throw error;
      const result = Array.isArray(data) ? data[0] : data;
      if (!result?.order_id || !result?.order_number || !result?.delivery_date || result.total_amount == null) {
        throw new Error('Server tidak mengembalikan data pesanan yang lengkap. Periksa antrean kasir sebelum mencoba memesan ulang.');
      }

      const message = [
        '*PESANAN WARUNG DARUL ILMI*',
        `Nomor: ${result.order_number}`,
        `Nama: ${customer.name}`,
        `Kategori: ${customer.gender}`,
        `Asrama: ${customer.dorm}`,
        `Kelas: ${customer.className}`,
        `Tanggal pengiriman: ${new Date(`${result.delivery_date}T00:00:00`).toLocaleDateString('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}`,
        '',
        '*Rincian pesanan:*',
        ...items.map(x => `- ${x.name} x${x.qty} = ${money(x.price * x.qty)}`),
        `*Total: ${money(result.total_amount)}*`,
        storeSettings.bank_name ? `Bank: ${storeSettings.bank_name}` : '',
        storeSettings.bank_account_number ? `Rekening: ${storeSettings.bank_account_number}` : '',
        storeSettings.bank_account_name ? `Atas nama: ${storeSettings.bank_account_name}` : '',
        customer.note ? `Catatan: ${customer.note}` : '',
        storeSettings.payment_instructions || 'Mohon konfirmasi pembayaran. Barang diserahkan setelah pembayaran diverifikasi.',
        'Silakan kirim bukti transfer berupa foto/screenshot langsung di chat WhatsApp ini. Bukti transfer tidak diunggah ke aplikasi.'
      ].filter(Boolean).join('\n');

      setCart([]);
      setCartOpen(false);
      setIdentity({ name: '', gender: customer.gender, dorm: '', className: '', phone: '', note: '' });

      if (!whatsappNumber) {
        setNotice(`Pesanan ${result.order_number} berhasil tersimpan. Admin belum mengisi nomor WhatsApp tujuan pada Pengaturan.`);
        return;
      }

      const whatsappUrl = `https://wa.me/${whatsappNumber}?text=${encodeURIComponent(message)}`;
      setWhatsappFallbackUrl(whatsappUrl);
      if (whatsappPopup && !whatsappPopup.closed) {
        try {
          whatsappPopup.location.replace(whatsappUrl);
          setNotice(`Pesanan ${result.order_number} berhasil tersimpan. WhatsApp sedang dibuka. Jika tidak terbuka, gunakan tautan Buka WhatsApp di bawah.`);
        } catch (_) {
          setNotice(`Pesanan ${result.order_number} berhasil tersimpan, tetapi WhatsApp tidak dapat dibuka otomatis. Gunakan tautan Buka WhatsApp di bawah.`);
        }
      } else {
        setNotice(`Pesanan ${result.order_number} berhasil tersimpan. Browser memblokir jendela otomatis; tekan Buka WhatsApp untuk mengirim rincian pesanan.`);
      }
    } catch (error) {
      if (whatsappPopup && !whatsappPopup.closed) {
        try { whatsappPopup.close(); } catch (_) { /* Ignore popup cleanup errors. */ }
      }
      setNotice(`Hasil penyimpanan belum dapat dipastikan: ${error?.message || 'Gangguan jaringan atau server.'}. Jangan langsung mengirim pesanan ulang; periksa antrean kasir terlebih dahulu.`);
    } finally {
      setOrderSubmitting(false);
    }
  }

'@
$content = $content.Substring(0, $startIndex) + $newFunction + $content.Substring($endIndex)

$buttonOld = @'
<button className="primary full" onClick={placeOrder}>Simpan pesanan & lanjut WhatsApp <span>→</span></button>
'@.Trim()
$buttonNew = @'
<button className="primary full" onClick={placeOrder} disabled={orderSubmitting}>{orderSubmitting ? 'Menyimpan pesanan…' : 'Simpan pesanan & lanjut WhatsApp'} <span>→</span></button>
'@.Trim()
if (-not $content.Contains($buttonOld)) {
    throw 'Tombol checkout tidak cocok dengan versi yang diaudit. Tidak ada perubahan file yang disimpan.'
}
$content = $content.Replace($buttonOld, $buttonNew)

$noticeOld = @'
{notice&&<div className="notice notice-toast" role="status"><span>{notice}</span><button onClick={()=>setNotice('')} aria-label="Tutup pemberitahuan">×</button></div>}
'@.Trim()
$noticeNew = $noticeOld + "`r`n      {whatsappFallbackUrl && <div className=\"notice whatsapp-fallback\" role=\"status\"><span>Pesanan sudah tersimpan. Tekan tautan ini untuk membuka WhatsApp dan kirim konfirmasi kepada kasir.</span><a className=\"primary\" href={whatsappFallbackUrl} target=\"_blank\" rel=\"noopener noreferrer\">Buka WhatsApp untuk mengirim pesanan</a><button type=\"button\" onClick={()=>setWhatsappFallbackUrl('')} aria-label=\"Tutup tautan WhatsApp\">Tutup</button></div>}"
if (-not $content.Contains($noticeOld)) {
    throw 'Area pemberitahuan checkout tidak ditemukan. Tidak ada perubahan file yang disimpan.'
}
$content = $content.Replace($noticeOld, $noticeNew)

$backupPath = "$appPath.bak-sebelum-fix-checkout-whatsapp"
if (Test-Path $backupPath) { throw "Cadangan sudah ada: $backupPath. Pindahkan cadangan lama terlebih dahulu." }
Copy-Item -LiteralPath $appPath -Destination $backupPath
Set-Content -LiteralPath $appPath -Value $content -Encoding UTF8

$check = Get-Content -LiteralPath $appPath -Raw -Encoding UTF8
$required = @('whatsappFallbackUrl', 'window.open(''about:blank''', 'whatsappPopup.location.replace(whatsappUrl)', 'Buka WhatsApp untuk mengirim pesanan', 'orderSubmitting', 'create_guest_order')
$missing = @($required | Where-Object { -not $check.Contains($_) })
if ($missing.Count -gt 0) {
    Copy-Item -LiteralPath $backupPath -Destination $appPath -Force
    throw "Validasi gagal ($($missing -join ', ')). File asli dipulihkan dari cadangan."
}
if ($check.Contains("window.open(`https://wa.me/")) {
    Copy-Item -LiteralPath $backupPath -Destination $appPath -Force
    throw 'Pola popup lama masih ditemukan. File asli dipulihkan.'
}
Write-Host 'Berhasil memperbarui src/App.jsx.' -ForegroundColor Green
Write-Host "Cadangan: $backupPath"
Write-Host 'Perubahan: popup WhatsApp dibuka saat klik, tautan cadangan ditampilkan, hasil RPC divalidasi, dan tombol checkout dinonaktifkan selama penyimpanan.'

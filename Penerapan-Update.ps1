$ErrorActionPreference = 'Stop'

$root = (Get-Location).Path
$appPath = Join-Path $root 'src/App.jsx'
$cssPath = Join-Path $root 'src/styles.css'
$migrationPath = Join-Path $root 'supabase/migrations/202611200003_staff_order_edit.sql'

foreach ($path in @($appPath, $cssPath, $migrationPath)) {
  if (-not (Test-Path $path)) { throw "File yang diperlukan tidak ditemukan: $path. Jalankan skrip dari folder utama proyek dan pastikan ZIP diekstrak dengan struktur foldernya." }
}

function Replace-Once([string]$Source, [string]$Old, [string]$New, [string]$Label) {
  $first = $Source.IndexOf($Old, [System.StringComparison]::Ordinal)
  if ($first -lt 0) { throw "Pola untuk '$Label' tidak ditemukan. Tidak ada perubahan lanjutan yang diterapkan." }
  $second = $Source.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
  if ($second -ge 0) { throw "Pola untuk '$Label' muncul lebih dari sekali. Hentikan agar kode tidak berubah di lokasi yang salah." }
  return $Source.Substring(0, $first) + $New + $Source.Substring($first + $Old.Length)
}

function Replace-All([string]$Source, [string]$Old, [string]$New, [string]$Label) {
  if (-not $Source.Contains($Old)) { throw "Pola untuk '$Label' tidak ditemukan." }
  return $Source.Replace($Old, $New)
}

$app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
$css = [System.IO.File]::ReadAllText($cssPath, [System.Text.Encoding]::UTF8)
$utf8 = New-Object System.Text.UTF8Encoding($false)

$backupApp = "$appPath.before-update-20261120.bak"
$backupCss = "$cssPath.before-update-20261120.bak"

# Data produk dan status pembayaran disimpan pada hasil pemetaan pesanan.
$app = Replace-Once $app `
"const items = (row.order_items || []).map(x => ({ id: x.product_id ?? x.id, name: x.product_name_snapshot, price: Number(x.unit_price_snapshot), qty: x.quantity }));" `
"const items = (row.order_items || []).map(x => ({ id: x.product_id ?? x.id, productId: x.product_id ?? null, name: x.product_name_snapshot, price: Number(x.unit_price_snapshot), qty: x.quantity }));" `
'mapping ID produk untuk editor'
$app = Replace-Once $app `
"note: row.customer_note || '', items, total: Number(row.total_amount || 0), status: row.status };" `
"note: row.customer_note || '', items, total: Number(row.total_amount || 0), status: row.status, paymentState: row.payment_state };" `
'mapping status pembayaran'

$stateAnchor = "  const [cashierGenderFilter, setCashierGenderFilter] = useState('Semua');"
$stateNew = @'
  const [cashierGenderFilter, setCashierGenderFilter] = useState('Semua');
  const [editingOrder, setEditingOrder] = useState(null);
  const [orderEditForm, setOrderEditForm] = useState(null);
  const [orderEditProducts, setOrderEditProducts] = useState([]);
  const [orderEditNewProduct, setOrderEditNewProduct] = useState('');
  const [orderEditBusy, setOrderEditBusy] = useState(false);
'@
$app = Replace-Once $app $stateAnchor $stateNew.TrimEnd([char[]]"`r`n") 'state dialog edit pesanan'

$editFunctions = @'
  async function openOrderEditor(order) {
    if (!isStaff || !order) return;
    if (profile?.role === 'cashier' && normalizeGender(order.customer.gender) !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin untuk mengubah pesanan dari jalur lain.');
      return;
    }
    setOrderEditBusy(true);
    try {
      const { data, error } = await supabase
        .from('products')
        .select('id,name,price,is_available')
        .eq('is_available', true)
        .order('name');
      if (error) throw error;
      setOrderEditProducts(data || []);
      setOrderEditForm({
        name: order.customer.name || '',
        gender: order.customer.gender || 'Putra',
        dorm: order.customer.dorm === '-' ? '' : (order.customer.dorm || ''),
        className: order.customer.className === '-' ? '' : (order.customer.className || ''),
        phone: order.customer.phone || '',
        note: order.note || '',
        deliveryDate: order.deliveryDate || '',
        items: order.items.map(item => ({ product_id: item.productId, name: item.name, price: Number(item.price || 0), quantity: Number(item.qty || 1) }))
      });
      setOrderEditNewProduct('');
      setEditingOrder(order);
    } catch (error) {
      setNotice(`Editor pesanan gagal dibuka: ${error?.message || 'Kesalahan jaringan.'}`);
    } finally {
      setOrderEditBusy(false);
    }
  }

  function addOrderEditProduct() {
    const product = orderEditProducts.find(item => String(item.id) === String(orderEditNewProduct));
    if (!product || !orderEditForm) return;
    setOrderEditForm(current => {
      const existing = current.items.find(item => String(item.product_id) === String(product.id));
      return {
        ...current,
        items: existing
          ? current.items.map(item => String(item.product_id) === String(product.id) ? { ...item, quantity: Math.min(50, Number(item.quantity || 0) + 1) } : item)
          : [...current.items, { product_id: product.id, name: product.name, price: Number(product.price || 0), quantity: 1 }]
      };
    });
    setOrderEditNewProduct('');
  }

  function updateOrderEditQuantity(index, value) {
    const quantity = Math.max(1, Math.min(50, Number.parseInt(value, 10) || 1));
    setOrderEditForm(current => ({ ...current, items: current.items.map((item, itemIndex) => itemIndex === index ? { ...item, quantity } : item) }));
  }

  function removeOrderEditItem(index) {
    setOrderEditForm(current => ({ ...current, items: current.items.filter((_, itemIndex) => itemIndex !== index) }));
  }

  async function saveOrderEdit(event) {
    event.preventDefault();
    if (!editingOrder || !orderEditForm || orderEditBusy) return;
    if (orderEditForm.name.trim().length < 2 || !orderEditForm.dorm.trim() || !orderEditForm.className.trim() || !orderEditForm.deliveryDate) {
      setNotice('Nama santri, asrama, kelas, dan tanggal pengiriman wajib diisi.');
      return;
    }
    if (!['Putra', 'Putri'].includes(orderEditForm.gender)) {
      setNotice('Kategori santri harus Putra atau Putri.');
      return;
    }
    if (!orderEditForm.items.length || orderEditForm.items.length > 30) {
      setNotice('Pesanan harus memiliki 1 sampai 30 jenis menu.');
      return;
    }
    const productIds = new Set(orderEditProducts.map(product => String(product.id)));
    const items = orderEditForm.items.map(item => ({ product_id: item.product_id, quantity: Number(item.quantity) }));
    if (items.some(item => !item.product_id || !productIds.has(String(item.product_id)) || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 50)) {
      setNotice('Ada menu lama yang sudah tidak tersedia. Hapus menu tersebut atau ganti dengan menu aktif sebelum menyimpan.');
      return;
    }
    const requestedTotal = items.reduce((sum, item) => {
      const product = orderEditProducts.find(row => String(row.id) === String(item.product_id));
      return sum + Number(product?.price || 0) * item.quantity;
    }, 0);
    if (['paid', 'pending_verification'].includes(editingOrder.paymentState) && requestedTotal !== Number(editingOrder.total || 0)) {
      setNotice('Pesanan memiliki pembayaran menunggu verifikasi atau sudah lunas. Perubahan menu/jumlah tidak boleh mengubah total tagihan.');
      return;
    }

    setOrderEditBusy(true);
    try {
      const { data, error } = await supabase.rpc('update_staff_order', {
        p_order_id: editingOrder.id,
        p_guest_name: orderEditForm.name.trim(),
        p_guest_gender: orderEditForm.gender,
        p_guest_dormitory: orderEditForm.dorm.trim(),
        p_guest_class: orderEditForm.className.trim(),
        p_guest_phone: orderEditForm.phone.trim() || null,
        p_customer_note: orderEditForm.note.trim() || null,
        p_delivery_date: orderEditForm.deliveryDate,
        p_items: items
      });
      if (error) throw error;
      const result = Array.isArray(data) ? data[0] : data;
      const orderNumber = editingOrder.number;
      setEditingOrder(null);
      setOrderEditForm(null);
      setNotice(`Pesanan ${orderNumber} berhasil diperbarui. Total: ${money(result?.total_amount ?? requestedTotal)}.`);
      await loadOrders();
      if (page === 'reports' && reportLoaded) await loadReportOrders();
      if (page === 'distribution') await loadDistributionOrders(effectiveDistributionDate);
    } catch (error) {
      setNotice(`Pesanan gagal diperbarui: ${error?.message || 'Kesalahan jaringan.'}`);
    } finally {
      setOrderEditBusy(false);
    }
  }

'@
$app = Replace-Once $app "  async function updateOrder(id,patch) {" ($editFunctions + "  async function updateOrder(id,patch) {") 'fungsi editor pesanan'

# Tombol penyerahan dapat dipakai kasir saat pesanan memang sudah diserahkan; distribusi hanya pemantauan.
$readyGuard = @'
    if (patch.status === 'delivered' && target.status !== 'ready') {
      setNotice('Pesanan hanya dapat ditandai diserahkan setelah berstatus Siap diserahkan.'); return;
    }

'@
$app = Replace-Once $app $readyGuard '' 'aturan status siap diserahkan lama'
$app = Replace-All $app 'onStatus={(id,v)=>updateOrder(id,{status:v})}/>' 'onStatus={(id,v)=>updateOrder(id,{status:v})} onEdit={openOrderEditor}/>' 'penghubung tombol edit pesanan'

# Format Excel diminta sederhana: satu baris per pesanan santri dan satu kolom untuk setiap menu.
$app = Replace-Once $app "const matrixHeaders = ['Nama Santri', 'Kelas', 'Asrama', 'Kategori', 'Tanggal Pengiriman', 'Nomor Pesanan', ...productNames, 'Total Pesanan', 'Status Pesanan'];" "const matrixHeaders = ['Nama Santri', 'Kelas', 'Asrama', ...productNames];" 'judul kolom Excel'
$rowPattern = '(?s)        matrixRows\.push\(\[\r?\n.*?\r?\n        \]\);'
$rowReplacement = @'
        matrixRows.push([
          order.customer.name || '', order.customer.className || '', order.customer.dorm || '',
          ...productNames.map(name => quantities.get(productKey(name)) || 0)
        ]);
'@
if (-not [regex]::IsMatch($app, $rowPattern)) { throw 'Pola baris Excel tidak ditemukan. Tidak ada perubahan lanjutan yang diterapkan.' }
$app = [regex]::Replace($app, $rowPattern, $rowReplacement.TrimEnd([char[]]"`r`n"), 1)

$reportButtonsOld = '<button className="primary" type="button" onClick={exportWorkbook} disabled={reportLoading||!reportLoaded||reportLimitReached}>Unduh Excel (.xlsx)</button>'
$reportButtonsNew = @'
<button className="primary" type="button" onClick={exportWorkbook} disabled={reportLoading||!reportLoaded||reportLimitReached}>Unduh Excel (.xlsx)</button><button type="button" onClick={exportPdfChecklist} disabled={reportLoading||!reportLoaded||reportLimitReached}>Ekspor PDF (ceklis)</button><button type="button" onClick={exportTxtSummary} disabled={reportLoading||!reportLoaded||reportLimitReached}>Unduh TXT</button>
'@
$app = Replace-Once $app $reportButtonsOld $reportButtonsNew.Trim() 'tombol ekspor Excel PDF TXT'
$app = Replace-Once $app 'Filter berdasarkan tanggal pengiriman dan kategori santri. Pratinjau serta seluruh lembar Excel mengikuti filter yang dipilih.' 'Filter berdasarkan tanggal pengiriman dan kategori santri. Excel, PDF ceklis distribusi, dan TXT rekap menu mengikuti filter yang dipilih.' 'keterangan halaman laporan'

$exportFunctions = @'
  function reportPeriodLabel() {
    const formatDate = value => value ? new Intl.DateTimeFormat('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(`${value}T00:00:00`)) : '';
    if (reportFrom && reportTo && reportFrom !== reportTo) return `${formatDate(reportFrom)} s.d. ${formatDate(reportTo)}`;
    return formatDate(reportFrom || reportTo) || 'Periode laporan';
  }

  function exportPdfChecklist() {
    if (!isAdmin || !reportLoaded || reportLoading || reportLimitReached || !reportOrders.length) {
      setNotice('Muat laporan yang lengkap terlebih dahulu sebelum membuat PDF.');
      return;
    }
    const rows = ['Putra', 'Putri'].map(gender => {
      const ordersForGender = reportOrders.filter(order => order.customer.gender === gender);
      if (!ordersForGender.length) return '';
      const body = ordersForGender.map(order => {
        const menu = order.items.map(item => `${escapeHtml(item.name)} x ${Number(item.qty)}`).join('<br>');
        return `<tr><td>${escapeHtml(order.customer.name)}</td><td>${escapeHtml(order.customer.className)}</td><td>${escapeHtml(order.customer.dorm)}</td><td>${menu}</td><td class="check-cell"><span class="check-box"></span></td></tr>`;
      }).join('');
      return `<section class="gender-section"><h2>Santri ${gender}</h2><table><thead><tr><th>Nama santri</th><th>Kelas</th><th>Asrama</th><th>Menu dan jumlah</th><th>Ceklis</th></tr></thead><tbody>${body}</tbody></table></section>`;
    }).join('');
    const html = `<!doctype html><html lang="id"><head><meta charset="utf-8"><title>Ceklis Distribusi Warung Darul Ilmi</title><style>
      *{box-sizing:border-box}body{font:12px Arial,sans-serif;color:#17251e;margin:24px}h1{font-size:20px;margin:0 0 5px}p{margin:0 0 18px;color:#59685f}.gender-section{margin:22px 0 28px}.gender-section h2{font-size:15px;background:#edf2ed;padding:8px;margin:0 0 8px}table{border-collapse:collapse;width:100%;table-layout:fixed}th,td{border:1px solid #aeb9b0;padding:8px;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#f4f5f2}th:nth-child(1){width:23%}th:nth-child(2){width:12%}th:nth-child(3){width:16%}th:nth-child(4){width:39%}th:nth-child(5){width:10%}.check-cell{text-align:center}.check-box{display:inline-block;width:17px;height:17px;border:1.5px solid #26382d;margin:2px}.empty{padding:12px;border:1px solid #aaa}@media print{body{margin:12mm}.gender-section{break-inside:avoid}tr{break-inside:avoid}h1{font-size:18px}}
    </style></head><body><h1>Warung Darul Ilmi — Ceklis Distribusi</h1><p>Periode: ${escapeHtml(reportPeriodLabel())} | Jumlah pesanan: ${reportOrders.length}</p>${rows || '<p class="empty">Tidak ada pesanan.</p>'}</body></html>`;
    const frame = document.createElement('iframe');
    frame.setAttribute('aria-hidden', 'true');
    frame.style.position = 'fixed'; frame.style.width = '1px'; frame.style.height = '1px'; frame.style.opacity = '0'; frame.style.border = '0';
    frame.onload = () => {
      try { frame.contentWindow.focus(); frame.contentWindow.print(); }
      catch { setNotice('Dialog cetak tidak dapat dibuka. Coba gunakan Chrome atau Edge terbaru.'); }
      frame.contentWindow.addEventListener('afterprint', () => frame.remove(), { once: true });
    };
    frame.srcdoc = html;
    document.body.appendChild(frame);
    setNotice('Dialog cetak dibuka. Pilih “Simpan sebagai PDF” pada tujuan printer untuk mengunduh PDF.');
  }

  async function exportTxtSummary() {
    if (!isAdmin || !reportLoaded || reportLoading || reportLimitReached || !reportOrders.length) {
      setNotice('Muat laporan yang lengkap terlebih dahulu sebelum membuat TXT.');
      return;
    }
    try {
      const { data: catalogProducts, error } = await supabase
        .from('products').select('id,name,categories(name)').order('name');
      if (error) throw error;
      const categoryById = new Map();
      const categoryByName = new Map();
      for (const product of catalogProducts || []) {
        const category = String(product.categories?.name || 'Tanpa kategori').trim();
        if (product.id !== undefined && product.id !== null) categoryById.set(String(product.id), category);
        if (product.name) categoryByName.set(String(product.name).trim().toLocaleLowerCase('id'), category);
      }
      const totals = { Putra: new Map(), Putri: new Map() };
      for (const order of reportOrders) {
        const gender = order.customer.gender === 'Putri' ? 'Putri' : 'Putra';
        for (const item of order.items) {
          const category = (item.productId !== null && item.productId !== undefined ? categoryById.get(String(item.productId)) : null)
            || categoryByName.get(String(item.name || '').trim().toLocaleLowerCase('id'))
            || 'Tanpa kategori';
          const key = `${category}\u0000${item.name}`;
          const current = totals[gender].get(key) || { category, name: item.name, quantity: 0 };
          current.quantity += Number(item.qty || 0);
          totals[gender].set(key, current);
        }
      }
      const lines = [`PESANAN ${reportPeriodLabel().toLocaleUpperCase('id-ID')}`, 'WARUNG DARUL ILMI', ''];
      for (const gender of ['Putra', 'Putri']) {
        lines.push(`SANTRI ${gender.toUpperCase()}`);
        const entries = [...totals[gender].values()];
        if (!entries.length) { lines.push('  - Tidak ada pesanan', ''); continue; }
        const categories = [...new Set(entries.map(entry => entry.category))].sort((a, b) => a.localeCompare(b, 'id'));
        for (const category of categories) {
          lines.push(`  ${category.toUpperCase()}`);
          entries.filter(entry => entry.category === category).sort((a, b) => a.name.localeCompare(b.name, 'id'))
            .forEach(entry => lines.push(`    - ${entry.name}: ${entry.quantity}`));
        }
        lines.push('');
      }
      lines.push(`Jumlah pesanan: ${reportOrders.length}`);
      const blob = new Blob([String.fromCharCode(0xFEFF) + lines.join('\r\n')], { type: 'text/plain;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `pesanan-warung-darul-ilmi-${reportFrom || reportTo || 'periode'}-${reportTo || reportFrom || ''}.txt`;
      document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
      setNotice('Rekap TXT berhasil diunduh, dipisahkan berdasarkan Putra/Putri dan kategori menu.');
    } catch (error) {
      setNotice(`Ekspor TXT gagal: ${error?.message || error}`);
    }
  }

'@
$app = Replace-Once $app '  function printKitchenTickets(list = distributionOrders) {' ($exportFunctions + '  function printKitchenTickets(list = distributionOrders) {') 'fungsi ekspor PDF dan TXT'

# Distribusi tidak lagi mencetak tiket atau mengubah status penyerahan.
$app = Replace-Once $app 'Hanya pesanan berstatus siap diserahkan yang dapat ditandai sudah diserahkan.' 'Status penyerahan diubah oleh kasir dari halaman antrean. Halaman ini hanya untuk pemantauan distribusi.' 'keterangan halaman distribusi'
$app = Replace-Once $app '<button className="primary" onClick={()=>printKitchenTickets()}>Cetak semua tiket dapur</button>' '' 'tombol cetak semua tiket dapur'
$app = Replace-Once $app '<button onClick={()=>printKitchenTickets([o])}>Cetak tiket</button>' '' 'tombol cetak tiket per santri'
$app = Replace-Once $app '<button onClick={loadOrders}>Muat ulang pesanan</button>' '<button onClick={()=>loadDistributionOrders(effectiveDistributionDate)}>Muat ulang pesanan</button>' 'muat ulang halaman distribusi'
$deliveredButtonOld = @'
<button className="primary" onClick={()=>updateOrder(o.id,{status:'delivered'})} disabled={o.status!=='ready'}>Tandai diserahkan</button>
'@
$app = Replace-Once $app $deliveredButtonOld.Trim() '' 'tombol serah terima di dapur'

# Dialog edit disematkan dalam halaman utama agar kasir dan admin memakai editor yang sama.
$modal = @'
    {editingOrder && orderEditForm && <div className="order-edit-overlay" onClick={() => !orderEditBusy && (setEditingOrder(null), setOrderEditForm(null))}>
      <section className="order-edit-modal" role="dialog" aria-modal="true" aria-labelledby="order-edit-title" onClick={event => event.stopPropagation()}>
        <div className="section-heading"><div><p className="eyebrow">UBAH PESANAN</p><h2 id="order-edit-title">{editingOrder.number}</h2><p className="muted">Perubahan akan disimpan ke database.</p></div><button type="button" onClick={() => { setEditingOrder(null); setOrderEditForm(null); }} disabled={orderEditBusy}>Tutup</button></div>
        {['paid', 'pending_verification'].includes(editingOrder.paymentState) && <p className="warning">Pesanan memiliki pembayaran menunggu verifikasi atau sudah lunas. Identitas dan catatan tetap dapat diperbarui, tetapi total menu/jumlah harus tetap sama dengan tagihan.</p>}
        <form onSubmit={saveOrderEdit} className="order-edit-form">
          <div className="order-edit-grid">
            <label>Nama santri<input value={orderEditForm.name} onChange={event => setOrderEditForm({ ...orderEditForm, name: event.target.value })} required /></label>
            <label>Kategori santri<select value={orderEditForm.gender} onChange={event => setOrderEditForm({ ...orderEditForm, gender: event.target.value })} disabled={profile?.role === 'cashier'}><option value="Putra">Putra</option><option value="Putri">Putri</option></select></label>
            <label>Asrama<input value={orderEditForm.dorm} onChange={event => setOrderEditForm({ ...orderEditForm, dorm: event.target.value })} required /></label>
            <label>Kelas<input value={orderEditForm.className} onChange={event => setOrderEditForm({ ...orderEditForm, className: event.target.value })} required /></label>
            <label>Nomor WhatsApp<input value={orderEditForm.phone} onChange={event => setOrderEditForm({ ...orderEditForm, phone: event.target.value })} /></label>
            <label>Tanggal pengiriman<input type="date" value={orderEditForm.deliveryDate} onChange={event => setOrderEditForm({ ...orderEditForm, deliveryDate: event.target.value })} required /></label>
          </div>
          <label>Catatan pesanan<textarea value={orderEditForm.note} onChange={event => setOrderEditForm({ ...orderEditForm, note: event.target.value })} rows="3" /></label>
          <div className="order-edit-items"><h3>Menu pesanan</h3>
            {orderEditForm.items.map((item, index) => {
              const product = orderEditProducts.find(row => String(row.id) === String(item.product_id));
              return <div className="order-edit-item" key={`${item.product_id || item.name}-${index}`}>
                <div><strong>{product?.name || item.name}</strong><small>{product ? money(product.price) : 'Menu lama tidak tersedia; hapus atau ganti dengan menu aktif.'}</small></div>
                <label>Jumlah<input type="number" min="1" max="50" value={item.quantity} onChange={event => updateOrderEditQuantity(index, event.target.value)} /></label>
                <button type="button" onClick={() => removeOrderEditItem(index)} disabled={orderEditBusy}>Hapus</button>
              </div>;
            })}
            <div className="order-edit-add"><label>Tambah menu aktif<select value={orderEditNewProduct} onChange={event => setOrderEditNewProduct(event.target.value)}><option value="">Pilih menu...</option>{orderEditProducts.map(product => <option key={product.id} value={product.id}>{product.name} — {money(product.price)}</option>)}</select></label><button type="button" onClick={addOrderEditProduct} disabled={!orderEditNewProduct || orderEditBusy}>Tambah menu</button></div>
          </div>
          <div className="order-edit-footer"><span>Perkiraan total: <strong>{money(orderEditForm.items.reduce((sum, item) => sum + Number(orderEditProducts.find(product => String(product.id) === String(item.product_id))?.price ?? item.price ?? 0) * Number(item.quantity || 0), 0))}</strong></span><button className="primary" type="submit" disabled={orderEditBusy}>{orderEditBusy ? 'Menyimpan...' : 'Simpan perubahan pesanan'}</button></div>
        </form>
      </section>
    </div>}
'@
$app = Replace-Once $app '    </main><footer>' ($modal + '    </main><footer>') 'dialog edit pesanan'

# Hilangkan fungsi cetak tiket lama yang sudah tidak dipakai.
$printPattern = '(?s)  function printKitchenTickets\(list = distributionOrders\) \{.*?\r?\n  \}\r?\n\r?\n  if \(staffLoginOpen\)'
if (-not [regex]::IsMatch($app, $printPattern)) { throw 'Fungsi cetak tiket lama tidak ditemukan.' }
$app = [regex]::Replace($app, $printPattern, '  if (staffLoginOpen)', 1)

# Ganti komponen daftar pesanan: hanya tiga tindakan yang diminta.
$orderListPattern = '(?s)function OrderList\(\{orders,onStatus\}\) \{.*?\r?\n\}\r?\nexport default App;'
$orderListReplacement = @'
function OrderList({orders,onStatus,onEdit}) {
  if(!orders.length)return <div className="panel empty">Belum ada pesanan di database.</div>;
  return <div className="order-list">{orders.map(o=>{
    const terminal = ['delivered','cancelled'].includes(o.status);
    return <article className="panel order-card" key={o.id}>
      <div className="order-top"><div><span className="category-label">{o.number}</span><h3>{o.customer.name}</h3><small>{new Date(o.createdAt).toLocaleString('id-ID')}</small></div><span className={`status ${o.status==='delivered'?'paid':''}`}>{statusLabels[o.status]||o.status}</span></div>
      <div className="order-meta"><span>{o.customer.gender}</span><span>{o.customer.dorm}</span><span>{o.customer.className}</span><span>Kirim: {o.deliveryDate}</span></div>
      {o.note&&<p className="fine-print">Catatan: {o.note}</p>}
      <div className="order-items">{o.items.map((x,i)=><div key={`${x.id}-${i}`}><span>{x.name} x {x.qty}</span><strong>{money(x.price*x.qty)}</strong></div>)}</div>
      <div className="order-bottom"><strong>{money(o.total)}</strong><div className="order-actions order-action-buttons">
        <button type="button" className="primary" onClick={()=>onStatus(o.id,'delivered')} disabled={terminal}>Diserahkan</button>
        <button type="button" onClick={()=>{if(window.confirm(`Batalkan pesanan ${o.number}?`)) onStatus(o.id,'cancelled');}} disabled={terminal}>Dibatalkan</button>
        <button type="button" onClick={()=>onEdit?.(o)}>Edit</button>
      </div></div>
    </article>;
  })}</div>;
}
export default App;
'@
if (-not [regex]::IsMatch($app, $orderListPattern)) { throw 'Komponen OrderList tidak ditemukan atau strukturnya berbeda.' }
$orderListEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $orderListReplacement.TrimEnd([char[]]"`r`n") }
$app = [regex]::Replace($app, $orderListPattern, $orderListEvaluator, 1)

if ((Test-Path $backupApp) -or (Test-Path $backupCss)) { throw 'File backup update ini sudah ada. Skrip tidak dijalankan dua kali untuk menghindari perubahan ganda.' }
Copy-Item $appPath $backupApp
Copy-Item $cssPath $backupCss
[System.IO.File]::WriteAllText($appPath, $app, $utf8)

$cssAddition = @'

/* Editor pesanan kasir/admin */
.order-action-buttons{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.order-action-buttons button{min-height:40px;border:1px solid #dcd8ca;background:#f8f6ef;border-radius:9px;padding:9px 13px;font:700 11px 'DM Sans';color:#244738;cursor:pointer}
.order-action-buttons button.primary{background:#174737;color:#fff;border:0}
.order-edit-overlay{position:fixed;inset:0;z-index:30;background:#102f28b8;display:grid;place-items:center;padding:16px}
.order-edit-modal{width:min(100%,780px);max-height:92vh;overflow:auto;background:#fffefa;border:1px solid #e9e4d7;border-radius:18px;padding:22px;box-shadow:0 24px 70px #10251e55}
.order-edit-modal .section-heading{margin:0 0 18px;align-items:center}
.order-edit-modal .section-heading h2{font-size:23px}
.order-edit-form{display:grid;gap:16px}
.order-edit-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:13px}
.order-edit-items{border-top:1px solid #e9e4d7;padding-top:13px}
.order-edit-items h3{font:600 17px 'Playfair Display';color:#173e32;margin:0 0 12px}
.order-edit-item{display:grid;grid-template-columns:minmax(0,1fr) 100px auto;gap:12px;align-items:end;padding:10px 0;border-bottom:1px solid #eeeadd}
.order-edit-item small{display:block;color:#829087;font-size:10px;margin-top:4px;line-height:1.4}
.order-edit-item button,.order-edit-add button,.order-edit-modal .section-heading>button,.order-edit-footer button{min-height:40px;border:1px solid #dcd8ca;background:#f8f6ef;border-radius:9px;padding:9px 13px;font:700 11px 'DM Sans';color:#244738;cursor:pointer}
.order-edit-add{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:end;margin-top:14px}
.order-edit-footer{display:flex;align-items:center;justify-content:space-between;gap:12px;border-top:1px solid #e9e4d7;padding-top:14px}
.order-edit-footer>span{font-size:12px;color:#627168}
.order-edit-footer strong{color:#174737;font-size:17px}
.order-edit-footer .primary{background:#174737;color:#fff;border:0}
@media(max-width:600px){.order-edit-overlay{padding:8px}.order-edit-modal{padding:15px;max-height:95vh}.order-edit-grid{grid-template-columns:1fr}.order-edit-item{grid-template-columns:minmax(0,1fr) 82px}.order-edit-item button{grid-column:1/-1}.order-edit-add{grid-template-columns:1fr}.order-edit-footer{align-items:stretch;flex-direction:column}.order-action-buttons{width:100%}.order-action-buttons button{flex:1}}
'@
if (-not $css.Contains('/* Editor pesanan kasir/admin */')) {
  [System.IO.File]::WriteAllText($cssPath, $css + $cssAddition, $utf8)
}

Write-Host ''
Write-Host 'Update tampilan berhasil diterapkan.' -ForegroundColor Green
Write-Host "Backup App.jsx : $backupApp"
Write-Host "Backup CSS     : $backupCss"
Write-Host "Migrasi SQL    : $migrationPath"
Write-Host 'Langkah berikutnya: jalankan migrasi SQL di Supabase sebelum menguji fitur edit pesanan.' -ForegroundColor Yellow

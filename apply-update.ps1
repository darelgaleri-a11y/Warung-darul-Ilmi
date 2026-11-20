$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appPath = Join-Path $root 'src\App.jsx'
$cssPath = Join-Path $root 'src\styles.css'
if (!(Test-Path $appPath)) { throw 'src\App.jsx tidak ditemukan. Ekstrak ZIP di root repository.' }
if (!(Test-Path $cssPath)) { throw 'src\styles.css tidak ditemukan. Ekstrak ZIP di root repository.' }

function Replace-Once {
  param([string]$Text,[string]$Old,[string]$New,[string]$Label)
  $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
  if ($first -lt 0) { throw "Bagian '$Label' tidak ditemukan. File mungkin bukan versi branch app yang diaudit." }
  $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
  if ($second -ge 0) { throw "Bagian '$Label' ditemukan lebih dari sekali. Tidak ada file yang ditulis." }
  return $Text.Substring(0,$first) + $New + $Text.Substring($first + $Old.Length)
}
function Replace-ExpectedCount {
  param([string]$Text,[string]$Old,[string]$New,[int]$Expected,[string]$Label)
  $count=0; $offset=0
  while ($true) {
    $found=$Text.IndexOf($Old,$offset,[System.StringComparison]::Ordinal)
    if ($found -lt 0) { break }
    $count++; $offset=$found+$Old.Length
  }
  if ($count -ne $Expected) { throw "Bagian '$Label' seharusnya muncul $Expected kali, ditemukan $count. Tidak ada file yang ditulis." }
  return $Text.Replace($Old,$New)
}

$app = [System.IO.File]::ReadAllText($appPath).Replace("`r`n","`n")
$css = [System.IO.File]::ReadAllText($cssPath).Replace("`r`n","`n")

$old=@'
paymentState: row.payment_state };
'@
$new=@'
paymentState: row.payment_state, deletedAt: row.deleted_at, deletedBy: row.deleted_by };
'@
$app=Replace-Once $app $old $new 'pemetaan soft delete'

$old=@'
  const [distributionDate, setDistributionDate] = useState('');
'@
$new=@'
  const [distributionFrom, setDistributionFrom] = useState('');
  const [distributionTo, setDistributionTo] = useState('');
'@
$app=Replace-Once $app $old $new 'state tanggal distribusi'

$old=@'
  const [cashierGenderFilter, setCashierGenderFilter] = useState('Semua');
'@
$new=@'
  const [cashierGenderFilter, setCashierGenderFilter] = useState('Semua');
  const [trashOrders, setTrashOrders] = useState([]);
  const [trashLoading, setTrashLoading] = useState(false);
  const [showTrash, setShowTrash] = useState(false);
'@
$app=Replace-Once $app $old $new 'state Sampah'

$old=@'
        .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
        .order('created_at',{ascending:false})
'@
$new=@'
        .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
        .is('deleted_at', null)
        .order('created_at',{ascending:false})
'@
$old=@'
        .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
        .order('created_at',{ascending:false})
'@
$new=@'
        .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
        .is('deleted_at', null)
        .order('created_at',{ascending:false})
'@
$app=Replace-Once $app $old $new 'filter antrean kasir'
$old=@'
          .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
          .order('created_at',{ascending:false})
'@
$new=@'
          .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
          .is('deleted_at', null)
          .order('created_at',{ascending:false})
'@
$app=Replace-Once $app $old $new 'filter laporan'

$old=@'
  }
  useEffect(() => { loadOrders(); }, [profile?.id, profile?.role, profile?.cashier_gender]);
'@
$new=@'
  }
  async function loadTrashOrders() {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return;
    if (profile.role === 'cashier' && !normalizeGender(profile.cashier_gender)) {
      setTrashOrders([]);
      return;
    }
    setTrashLoading(true);
    try {
      let query = supabase.from('orders')
        .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
        .not('deleted_at', 'is', null)
        .order('deleted_at', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(200);
      if (profile.role === 'cashier') query = query.eq('guest_gender', normalizeGender(profile.cashier_gender));
      const { data, error } = await query;
      if (error) throw error;
      setTrashOrders((data || []).map(mapOrder));
    } catch (error) {
      setNotice(`Gagal memuat Sampah pesanan: ${error?.message || 'Kesalahan jaringan.'}`);
    } finally {
      setTrashLoading(false);
    }
  }
  useEffect(() => { loadOrders(); }, [profile?.id, profile?.role, profile?.cashier_gender]);
  useEffect(() => {
    if (page === 'cashier' && isStaff) loadTrashOrders();
  }, [page, profile?.id, profile?.role, profile?.cashier_gender, ordersRealtimeVersion]);
'@
$app=Replace-Once $app $old $new 'pemuat daftar Sampah'

$old=@'
  const availableDeliveryDates = [...new Set(scopedOrders.map(o=>o.deliveryDate).filter(Boolean))].sort();
  const suggestedDistributionDate = availableDeliveryDates.find(d=>d >= new Date().toISOString().slice(0,10)) || availableDeliveryDates.at(-1) || nextDeliveryDate || new Date().toISOString().slice(0,10);
  const effectiveDistributionDate = distributionDate || suggestedDistributionDate;
  const effectiveDistributionGender = profile?.role === 'cashier' ? cashierGender : distributionGender;
  const distributionOrders = distributionRows.filter(o => !effectiveDistributionGender || effectiveDistributionGender === 'Semua' || o.customer.gender === effectiveDistributionGender);
  const distributionGroups = Object.values(distributionOrders.reduce((acc, order) => { const key = `${order.customer.gender}  |  ${order.customer.dorm || 'Tanpa asrama'}`; (acc[key] ||= []).push(order); return acc; }, {})).sort((a,b) => `${a[0].customer.gender}-${a[0].customer.dorm}`.localeCompare(`${b[0].customer.gender}-${b[0].customer.dorm}`,'id'));
  const invalidReportRange = Boolean(reportFrom && reportTo && reportFrom > reportTo);
'@
$new=@'
  const availableDeliveryDates = [...new Set(scopedOrders.map(o=>o.deliveryDate).filter(Boolean))].sort();
  const suggestedDistributionDate = availableDeliveryDates.find(d=>d >= new Date().toISOString().slice(0,10)) || availableDeliveryDates.at(-1) || nextDeliveryDate || new Date().toISOString().slice(0,10);
  const effectiveDistributionFrom = distributionFrom || suggestedDistributionDate;
  const effectiveDistributionTo = distributionTo || effectiveDistributionFrom;
  const invalidDistributionRange = Boolean(effectiveDistributionFrom && effectiveDistributionTo && effectiveDistributionFrom > effectiveDistributionTo);
  const effectiveDistributionGender = profile?.role === 'cashier' ? cashierGender : distributionGender;
  const distributionOrders = distributionRows.filter(o => !effectiveDistributionGender || effectiveDistributionGender === 'Semua' || o.customer.gender === effectiveDistributionGender);
  const distributionGroups = Object.values(distributionOrders.reduce((acc, order) => { const key = `${order.deliveryDate}::${order.customer.gender}::${order.customer.dorm || 'Tanpa asrama'}`; (acc[key] ||= []).push(order); return acc; }, {})).sort((a,b) => `${a[0].deliveryDate}-${a[0].customer.gender}-${a[0].customer.dorm}`.localeCompare(`${b[0].deliveryDate}-${b[0].customer.gender}-${b[0].customer.dorm}`,'id'));
  const invalidReportRange = Boolean(reportFrom && reportTo && reportFrom > reportTo);
'@
$app=Replace-Once $app $old $new 'perhitungan rentang tanggal'

$old=@'
  async function loadDistributionOrders(date = effectiveDistributionDate) {
    if (!supabase || !isStaff || !date) return;
    const requestId = ++distributionLoadVersionRef.current;
    const PAGE_SIZE = 500;
    const MAX_ROWS = 20000;
    let allRows = [];
    let reachedLimit = false;
    setDistributionLoading(true);
    setDistributionRows([]);
    setDistributionLimitReached(false);
    try {
      for (let from = 0; from < MAX_ROWS; from += PAGE_SIZE) {
        let query = supabase.from('orders')
          .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
          .eq('delivery_date', date)
          .order('created_at',{ascending:false})
          .order('id',{ascending:false})
          .range(from, from + PAGE_SIZE - 1);
        if (profile?.role === 'cashier') query = query.eq('guest_gender', normalizeGender(profile.cashier_gender));
        const {data,error} = await query;
        if (error) throw error;
        const rows = Array.isArray(data) ? data : [];
        allRows = allRows.concat(rows);
        if (rows.length < PAGE_SIZE) break;
        if (from + PAGE_SIZE >= MAX_ROWS) reachedLimit = true;
      }
      if (requestId !== distributionLoadVersionRef.current) return;
      setDistributionRows(allRows.map(mapOrder));
      setDistributionLimitReached(reachedLimit);
      if (reachedLimit) setNotice('Daftar distribusi mencapai batas 20.000 pesanan untuk satu tanggal. Periksa pembagian tanggal atau hubungi admin.');
    } catch (error) {
      if (requestId === distributionLoadVersionRef.current) setNotice(`Gagal memuat pesanan distribusi: ${error?.message || 'Kesalahan jaringan.'}`);
    } finally {
      if (requestId === distributionLoadVersionRef.current) setDistributionLoading(false);
    }
  }
  useEffect(() => {
    if (page === 'distribution' && isStaff && effectiveDistributionDate) loadDistributionOrders(effectiveDistributionDate);
    else if (page !== 'distribution') setDistributionRows([]);
  }, [page, profile?.id, profile?.role, profile?.cashier_gender, effectiveDistributionDate, ordersRealtimeVersion]);
'@
$new=@'
  async function loadDistributionOrders(fromDate = effectiveDistributionFrom, toDate = effectiveDistributionTo) {
    if (!supabase || !isStaff || !fromDate || !toDate) return;
    if (fromDate > toDate) {
      setNotice('Tanggal mulai distribusi tidak boleh melewati tanggal akhir.');
      return;
    }
    const requestId = ++distributionLoadVersionRef.current;
    const PAGE_SIZE = 500;
    const MAX_ROWS = 20000;
    let allRows = [];
    let reachedLimit = false;
    setDistributionLoading(true);
    setDistributionRows([]);
    setDistributionLimitReached(false);
    try {
      for (let from = 0; from < MAX_ROWS; from += PAGE_SIZE) {
        let query = supabase.from('orders')
          .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
          .gte('delivery_date', fromDate)
          .lte('delivery_date', toDate)
          .is('deleted_at', null)
          .order('delivery_date', { ascending: true })
          .order('created_at', { ascending: false })
          .order('id', { ascending: false })
          .range(from, from + PAGE_SIZE - 1);
        if (profile?.role === 'cashier') query = query.eq('guest_gender', normalizeGender(profile.cashier_gender));
        const {data,error} = await query;
        if (error) throw error;
        const rows = Array.isArray(data) ? data : [];
        allRows = allRows.concat(rows);
        if (rows.length < PAGE_SIZE) break;
        if (from + PAGE_SIZE >= MAX_ROWS) reachedLimit = true;
      }
      if (requestId !== distributionLoadVersionRef.current) return;
      setDistributionRows(allRows.map(mapOrder));
      setDistributionLimitReached(reachedLimit);
      if (reachedLimit) setNotice('Daftar distribusi mencapai batas 20.000 pesanan untuk rentang tanggal ini. Persempit rentang tanggal atau hubungi admin.');
    } catch (error) {
      if (requestId === distributionLoadVersionRef.current) setNotice(`Gagal memuat pesanan distribusi: ${error?.message || 'Kesalahan jaringan.'}`);
    } finally {
      if (requestId === distributionLoadVersionRef.current) setDistributionLoading(false);
    }
  }
  useEffect(() => {
    if (page === 'distribution' && isStaff && effectiveDistributionFrom && effectiveDistributionTo && !invalidDistributionRange) loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo);
    else if (page !== 'distribution') setDistributionRows([]);
  }, [page, profile?.id, profile?.role, profile?.cashier_gender, effectiveDistributionFrom, effectiveDistributionTo, invalidDistributionRange, ordersRealtimeVersion]);
'@
$app=Replace-Once $app $old $new 'query distribusi rentang tanggal'

$app=Replace-ExpectedCount $app "loadDistributionOrders(effectiveDistributionDate)" "loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo)" 3 'pemanggilan ulang distribusi'

$old=@'
  async function saveSettings(e) {
'@
$new=@'
  async function softDeleteOrder(id) {
    if (!supabase || !isStaff) return;
    const target = orders.find(order => order.id === id);
    if (!target) { setNotice('Pesanan tidak ditemukan pada antrean aktif. Muat ulang antrean.'); return; }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin menghapus pesanan dari jalur lain.');
      return;
    }
    try {
      const { error } = await supabase.rpc('soft_delete_staff_order', { p_order_id: id });
      if (error) throw error;
      setNotice(`Pesanan ${target.number} dipindahkan ke Sampah. Pesanan dapat dipulihkan selama 3 hari.`);
      await Promise.all([loadOrders(), loadTrashOrders()]);
    } catch (error) {
      setNotice(`Pesanan gagal dipindahkan ke Sampah: ${error?.message || 'Kesalahan jaringan.'}`);
    }
  }

  async function restoreOrder(id) {
    if (!supabase || !isStaff) return;
    const target = trashOrders.find(order => order.id === id);
    if (!target) { setNotice('Pesanan tidak ditemukan di Sampah. Muat ulang data.'); return; }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin memulihkan pesanan dari jalur lain.');
      return;
    }
    try {
      const { error } = await supabase.rpc('restore_staff_order', { p_order_id: id });
      if (error) throw error;
      setNotice(`Pesanan ${target.number} berhasil dipulihkan ke antrean aktif.`);
      await Promise.all([loadOrders(), loadTrashOrders()]);
    } catch (error) {
      setNotice(`Pesanan gagal dipulihkan: ${error?.message || 'Kesalahan jaringan.'}`);
    }
  }

  async function saveSettings(e) {
'@
$app=Replace-Once $app $old $new 'aksi hapus dan pulihkan pesanan'

# JSX halaman kasir ditulis pada satu baris di versi repository ini.
$old='</div><div className="stats"><div className="stat-card"><small>Menunggu (pesanan dimuat)</small>'
$new='</div>{!showTrash&&<div className="stats"><div className="stat-card"><small>Menunggu (pesanan dimuat)</small>'
$app=Replace-Once $app $old $new 'sembunyikan statistik di tab Sampah'

$old="<strong>{scopedOrders.filter(o=>o.status==='ready').length}</strong></div></div><div className=`"toolbar`"><h2>Antrean pesanan</h2>"
$new="<strong>{scopedOrders.filter(o=>o.status==='ready').length}</strong></div></div>}<div className=`"toolbar`"><h2>{showTrash?'Sampah pesanan':'Antrean pesanan'}</h2><div className=`"cashier-view-tabs`"><button type=`"button`" className={!showTrash?'active':''} onClick={()=>setShowTrash(false)}>Antrean aktif ({orders.length})</button><button type=`"button`" className={showTrash?'active':''} onClick={()=>setShowTrash(true)}>Sampah ({trashOrders.length})</button></div>"
$app=Replace-Once $app $old $new 'tab antrean aktif dan Sampah'

$old='<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Cari nama, tiket, asrama..."/>'
$new='{!showTrash&&<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Cari nama, tiket, asrama..."/>}'
$app=Replace-Once $app $old $new 'pencarian antrean aktif'

$old=@'
<label className="cashier-gender-filter">Jalur pesanan<select aria-label="Filter jalur kasir" value={profile?.role==='cashier'?cashierGender:cashierGenderFilter} onChange={e=>setCashierGenderFilter(e.target.value)} disabled={profile?.role==='cashier'}><option value="Semua">Semua jalur (Putra & Putri)</option><option value="Putra">Khusus Putra</option><option value="Putri">Khusus Putri</option></select>{profile?.role==='cashier'&&<small>Filter dikunci sesuai penugasan akun kasir.</small>}</label>
'@
$new=@'
{!showTrash&&<label className="cashier-gender-filter">Jalur pesanan<select aria-label="Filter jalur kasir" value={profile?.role==='cashier'?cashierGender:cashierGenderFilter} onChange={e=>setCashierGenderFilter(e.target.value)} disabled={profile?.role==='cashier'}><option value="Semua">Semua jalur (Putra & Putri)</option><option value="Putra">Khusus Putra</option><option value="Putri">Khusus Putri</option></select>{profile?.role==='cashier'&&<small>Filter dikunci sesuai penugasan akun kasir.</small>}</label>}
'@
$app=Replace-Once $app $old.TrimEnd([char[]]@("`r","`n")) $new.TrimEnd([char[]]@("`r","`n")) 'filter gender kasir'

$old='<select aria-label="Filter status pesanan" value={filter} onChange={e=>setFilter(e.target.value)}><option>Semua</option><option>Menunggu</option><option>Dikonfirmasi</option><option>Diproses</option><option>Siap diserahkan</option><option>Sudah diserahkan</option><option>Dibatalkan</option></select>'
$new='{!showTrash&&<select aria-label="Filter status pesanan" value={filter} onChange={e=>setFilter(e.target.value)}><option>Semua</option><option>Menunggu</option><option>Dikonfirmasi</option><option>Diproses</option><option>Siap diserahkan</option><option>Sudah diserahkan</option><option>Dibatalkan</option></select>}'
$app=Replace-Once $app $old $new 'filter status kasir'

$old='<button onClick={loadOrders}>Muat ulang</button>'
$new='{!showTrash&&<button onClick={loadOrders}>Muat ulang</button>}{showTrash&&<button onClick={loadTrashOrders}>Muat ulang Sampah</button>}'
$app=Replace-Once $app $old $new 'tombol muat ulang daftar'

$old='{loadingOrders&&<p className="muted">Memuat pesanan...</p>}'
$new='{!showTrash&&loadingOrders&&<p className="muted">Memuat pesanan...</p>}{showTrash&&trashLoading&&<p className="muted">Memuat Sampah pesanan...</p>}'
$app=Replace-Once $app $old $new 'indikator pemuatan kasir'

$old='<OrderList orders={filteredOrders} onStatus={(id,v)=>updateOrder(id,{status:v})} onEdit={openOrderEditor}/>'
$new='<OrderList orders={showTrash?trashOrders:filteredOrders} onStatus={(id,v)=>updateOrder(id,{status:v})} onEdit={openOrderEditor} onDelete={softDeleteOrder} onRestore={restoreOrder} trashMode={showTrash}/>'
$app=Replace-Once $app $old $new 'sumber data komponen daftar pesanan'

$old='<span className="muted">Menampilkan {orders.length} pesanan terbaru yang sudah dimuat.</span>'
$new='<span className="muted">{showTrash?`Menampilkan ${trashOrders.length} pesanan di Sampah (maksimal 200).`:`Menampilkan ${orders.length} pesanan terbaru menurut waktu pemesanan.`}</span>'
$app=Replace-Once $app $old $new 'keterangan jumlah daftar pesanan'

$old='{ordersHasMore&&<button type="button" onClick={()=>loadOrders({append:true})} disabled={loadingOrders||ordersLoadingMore}>'
$new='{!showTrash&&ordersHasMore&&<button type="button" onClick={()=>loadOrders({append:true})} disabled={loadingOrders||ordersLoadingMore}>'
$app=Replace-Once $app $old $new 'pagination hanya antrean aktif'

$old='<label>Tanggal pengiriman<input type="date" value={effectiveDistributionDate} onChange={e=>setDistributionDate(e.target.value)}/></label>'
$new='<label>Dari tanggal pengiriman<input type="date" value={effectiveDistributionFrom} onChange={e=>setDistributionFrom(e.target.value)}/></label><label>Sampai tanggal pengiriman<input type="date" value={effectiveDistributionTo} min={effectiveDistributionFrom} onChange={e=>setDistributionTo(e.target.value)}/></label>'
$app=Replace-Once $app $old $new 'input tanggal mulai dan akhir'

$old='<button onClick={()=>loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo)}>Muat ulang pesanan</button>'
$new='<button onClick={()=>loadDistributionOrders(effectiveDistributionFrom,effectiveDistributionTo)} disabled={invalidDistributionRange}>Muat ulang pesanan</button>'
$app=Replace-Once $app $old $new 'tombol muat ulang distribusi'

$old='{distributionLoading&&<p className="muted">Memuat semua pesanan pada tanggal distribusi...</p>}'
$new='{invalidDistributionRange&&<p className="notice">Tanggal mulai tidak boleh melewati tanggal akhir.</p>}{distributionLoading&&<p className="muted">Memuat pesanan pada rentang tanggal pengiriman...</p>}'
$app=Replace-Once $app $old $new 'pesan validasi rentang distribusi'

$old='<small>Pesanan pada tanggal ini</small>'
$new='<small>Pesanan pada rentang tanggal</small>'
$app=Replace-Once $app $old $new 'label jumlah pesanan distribusi'

$old='Belum ada pesanan pada {effectiveDistributionDate}. Pilih tanggal lain atau muat ulang pesanan.'
$new='Belum ada pesanan pada rentang {effectiveDistributionFrom} sampai {effectiveDistributionTo}. Ubah rentang tanggal atau muat ulang pesanan.'
$app=Replace-Once $app $old $new 'pesan kosong distribusi'

$old='key={`${group[0].customer.gender}-${group[0].customer.dorm}`}'
$new='key={`${group[0].deliveryDate}-${group[0].customer.gender}-${group[0].customer.dorm}`}'
$app=Replace-Once $app $old $new 'pemisahan grup per tanggal'

$old='<h2>{group[0].customer.gender}  |  {group[0].customer.dorm}</h2>'
$new='<h2>{new Date(`${group[0].deliveryDate}T00:00:00`).toLocaleDateString(`id-ID`,{day:`numeric`,month:`long`,year:`numeric`})} | {group[0].customer.gender} | {group[0].customer.dorm}</h2>'
$app=Replace-Once $app $old $new 'judul grup distribusi'

$old='<p className="muted">{o.customer.className}  |  {o.items.reduce((n,i)=>n+i.qty,0)} item  |  {money(o.total)}</p>'
$new='<p className="muted">{o.customer.className}  |  {o.items.reduce((n,i)=>n+i.qty,0)} item  |  {money(o.total)}</p><p className="fine-print">Dipesan: {new Date(o.createdAt).toLocaleString(`id-ID`)} | Pengiriman: {o.deliveryDate}</p>'
$app=Replace-Once $app $old $new 'informasi tanggal pada kartu distribusi'

$old=@'
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
'@
$new=@'
function OrderList({orders,onStatus,onEdit,onDelete,onRestore,trashMode=false}) {
  if(!orders.length)return <div className="panel empty">{trashMode?'Sampah kosong. Pesanan yang dihapus akan muncul di sini.':'Belum ada pesanan di database.'}</div>;
  return <div className="order-list">{orders.map(o=>{
    const terminal = ['delivered','cancelled'].includes(o.status);
    const deletedAt = o.deletedAt ? new Date(o.deletedAt) : null;
    const restoreUntil = deletedAt ? new Date(deletedAt.getTime() + 3 * 24 * 60 * 60 * 1000) : null;
    return <article className="panel order-card" key={o.id}>
      <div className="order-top"><div><span className="category-label">{o.number}</span><h3>{o.customer.name}</h3><small>Dipesan: {new Date(o.createdAt).toLocaleString('id-ID')}</small></div><span className={`status ${o.status==='delivered'?'paid':''}`}>{statusLabels[o.status]||o.status}</span></div>
      <div className="order-meta"><span>{o.customer.gender}</span><span>{o.customer.dorm}</span><span>{o.customer.className}</span><span>Pengiriman: {o.deliveryDate}</span></div>
      {o.note&&<p className="fine-print">Catatan: {o.note}</p>}
      <div className="order-items">{o.items.map((x,i)=><div key={`${x.id}-${i}`}><span>{x.name} x {x.qty}</span><strong>{money(x.price*x.qty)}</strong></div>)}</div>
      <div className="order-bottom"><strong>{money(o.total)}</strong><div className="order-actions order-action-buttons">
        {trashMode ? <>
          <small className="trash-retention">Dihapus: {deletedAt?.toLocaleString('id-ID') || '-'}<br/>Batas pemulihan: {restoreUntil?.toLocaleString('id-ID') || '-'}</small>
          <button type="button" className="restore" onClick={()=>{if(window.confirm(`Pulihkan pesanan ${o.number} ke antrean aktif?`)) onRestore?.(o.id);}}>Pulihkan</button>
        </> : <>
          <button type="button" className="primary" onClick={()=>onStatus(o.id,'delivered')} disabled={terminal}>Diserahkan</button>
          <button type="button" onClick={()=>{if(window.confirm(`Batalkan pesanan ${o.number}?`)) onStatus(o.id,'cancelled');}} disabled={terminal}>Dibatalkan</button>
          <button type="button" onClick={()=>onEdit?.(o)}>Edit</button>
          <button type="button" className="danger" onClick={()=>{if(window.confirm(`Pindahkan pesanan ${o.number} ke Sampah? Pesanan dapat dipulihkan selama 3 hari, lalu dihapus permanen.`)) onDelete?.(o.id);}}>Hapus</button>
        </>}
      </div></div>
    </article>;
  })}</div>;
}
'@
$app=Replace-Once $app $old $new 'komponen kartu pesanan'

$css += @'

/* WDI update: tab Sampah, soft delete, dan filter rentang distribusi */
.cashier-view-tabs{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.cashier-view-tabs button{min-height:40px;border:1px solid #dcd8ca;background:#f8f6ef;border-radius:9px;padding:8px 13px;font:700 11px 'DM Sans';color:#244738;cursor:pointer}
.cashier-view-tabs button.active{background:#174737;color:#fff;border-color:#174737}
.order-action-buttons button.danger{background:#fff2ef;color:#9b3425;border:1px solid #efc8bf}
.order-action-buttons button.restore{background:#edf6ef;color:#195b37;border:1px solid #bddbc7}
.trash-retention{display:block;align-self:center;color:#7c7160;font-size:10px;line-height:1.5}
.distribution-tools{align-items:end}
@media(max-width:600px){.cashier-view-tabs{width:100%}.cashier-view-tabs button{flex:1}.trash-retention{width:100%}}
'@

$migrationPath=Join-Path $root 'supabase\migrations\202611200004_staff_order_soft_delete.sql'
if (!(Test-Path $migrationPath)) { throw 'File migrasi SQL tidak ditemukan. Ekstrak semua file ZIP ke root repository.' }

# Semua validasi patch harus lolos sebelum backup dan file sumber ditulis.
Copy-Item $appPath "$appPath.before-wdi-update" -Force
Copy-Item $cssPath "$cssPath.before-wdi-update" -Force
$utf8NoBom=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($appPath,$app,$utf8NoBom)
[System.IO.File]::WriteAllText($cssPath,$css,$utf8NoBom)

Write-Host ''
Write-Host 'Update kode Warung Darul Ilmi berhasil diterapkan.' -ForegroundColor Green
Write-Host 'Backup: src\App.jsx.before-wdi-update dan src\styles.css.before-wdi-update'
Write-Host 'Selanjutnya jalankan migration SQL di Supabase, lalu npm run build.'

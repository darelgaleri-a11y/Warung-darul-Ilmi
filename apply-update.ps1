$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$appPath = Join-Path $root 'src\App.jsx'
$cssPath = Join-Path $root 'src\styles.css'
if (!(Test-Path $appPath)) { throw 'src\App.jsx tidak ditemukan. Ekstrak ZIP di folder utama repository Warung Darul Ilmi.' }
if (!(Test-Path $cssPath)) { throw 'src\styles.css tidak ditemukan. Ekstrak ZIP di folder utama repository Warung Darul Ilmi.' }
function Replace-Once {
  param([string]$Text,[string]$Old,[string]$New,[string]$Label)
  $a = $Text.IndexOf($Old, [StringComparison]::Ordinal)
  if ($a -lt 0) { throw "Bagian '$Label' tidak ditemukan. Repository lokal mungkin berbeda dari branch app." }
  if ($Text.IndexOf($Old, $a + $Old.Length, [StringComparison]::Ordinal) -ge 0) {
    throw "Bagian '$Label' ditemukan lebih dari sekali. Tidak ada file yang ditulis."
  }
  return ($Text.Substring(0, $a) + $New + $Text.Substring($a + $Old.Length))
}
$app=[IO.File]::ReadAllText($appPath,[Text.Encoding]::UTF8).Replace("`r`n","`n")
$css=[IO.File]::ReadAllText($cssPath,[Text.Encoding]::UTF8).Replace("`r`n","`n")
$old=@'
function normalizeGender(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'putra') return 'Putra';
  if (normalized === 'putri') return 'Putri';
  return '';
}
'@
$new=@'
function normalizeGender(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'putra') return 'Putra';
  if (normalized === 'putri') return 'Putri';
  return '';
}
function localDateStartIso(value, offsetDays = 0) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ''))) return null;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(year, month - 1, day, 0, 0, 0, 0);
  date.setDate(date.getDate() + offsetDays);
  return date.toISOString();
}
'@
$app=Replace-Once $app $old $new 'helper tanggal lokal'
$app=Replace-Once $app "  const [filter, setFilter] = useState('Semua');`n" '' 'state filter status'
$old="  const [cashierGenderFilter, setCashierGenderFilter] = useState('Semua');`n"
$new=$old+"  const [cashierOrderFrom, setCashierOrderFrom] = useState('');`n  const [cashierOrderTo, setCashierOrderTo] = useState('');`n"
$app=Replace-Once $app $old $new 'state rentang tanggal'
$app=Replace-Once $app "const statusValues = Object.fromEntries(Object.entries(statusLabels).map(([k,v]) => [v,k]));`n" '' 'pemetaan status tidak dipakai'
$old="  const reportLoadInFlightRef = useRef(false);`n"
$new=$old+"  const cashierOrderRangeRef = useRef({ from: '', to: '', enabled: false });`n  cashierOrderRangeRef.current = { from: cashierOrderFrom, to: cashierOrderTo, enabled: page === 'cashier' };`n"
$app=Replace-Once $app $old $new 'referensi tanggal terbaru'
$old="    if (ordersLoadInFlightRef.current) return;`n"
$new=@'
    if (ordersLoadInFlightRef.current) {
      ordersRefreshQueuedRef.current = true;
      return;
    }
    const currentRange = cashierOrderRangeRef.current;
    if (currentRange.enabled && currentRange.from && currentRange.to && currentRange.from > currentRange.to) {
      setOrders([]);
      setOrdersHasMore(false);
      return;
    }
'@
$app=Replace-Once $app $old $new 'validasi rentang dan antrean request'
$old=@'
        .range(from, from + PAGE_SIZE - 1);
      if (profile.role === 'cashier') query = query.eq('guest_gender', normalizeGender(profile.cashier_gender));
'@
$new=@'
        .range(from, from + PAGE_SIZE - 1);
      const dateRange = cashierOrderRangeRef.current;
      if (dateRange.enabled && dateRange.from) query = query.gte('created_at', localDateStartIso(dateRange.from));
      if (dateRange.enabled && dateRange.to) query = query.lt('created_at', localDateStartIso(dateRange.to, 1));
      if (profile.role === 'cashier') query = query.eq('guest_gender', normalizeGender(profile.cashier_gender));
'@
$app=Replace-Once $app $old $new 'query created_at rentang tanggal'
$old="  useEffect(() => { loadOrders(); }, [profile?.id, profile?.role, profile?.cashier_gender]);`n"
$new=@'
  useEffect(() => { loadOrders(); }, [profile?.id, profile?.role, profile?.cashier_gender]);
  useEffect(() => {
    if (page === 'cashier' && isStaff) loadOrders();
    else if (page !== 'cashier' && (cashierOrderFrom || cashierOrderTo)) loadOrders();
  }, [cashierOrderFrom, cashierOrderTo, page, profile?.id, profile?.role]);
'@
$app=Replace-Once $app $old $new 'muat ulang ketika tanggal berubah'
$old=@'
  const filteredOrders = scopedOrders.filter(o => (filter==='Semua'||o.status===statusValues[filter]) && (effectiveCashierGenderFilter==='Semua'||o.customer.gender===effectiveCashierGenderFilter) && `${o.number} ${o.customer.name} ${o.customer.dorm} ${o.customer.className}`.toLowerCase().includes(search.trim().toLowerCase()));
'@
$new=@'
  const invalidCashierOrderRange = Boolean(cashierOrderFrom && cashierOrderTo && cashierOrderFrom > cashierOrderTo);
  const filteredOrders = scopedOrders.filter(o => (effectiveCashierGenderFilter==='Semua'||o.customer.gender===effectiveCashierGenderFilter) && `${o.number} ${o.customer.name} ${o.customer.dorm} ${o.customer.className}`.toLowerCase().includes(search.trim().toLowerCase()));
'@
$app=Replace-Once $app $old $new 'filter lokal tanpa status'
$old=@'
<div className="toolbar"><h2>{showTrash?'Sampah pesanan':'Antrean pesanan'}</h2><div className="cashier-view-tabs"><button type="button" className={!showTrash?'active':''} onClick={()=>setShowTrash(false)}>Antrean aktif ({orders.length})</button><button type="button" className={showTrash?'active':''} onClick={()=>setShowTrash(true)}>Sampah ({trashOrders.length})</button></div>{!showTrash&&<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Cari nama, tiket, asrama..."/>
'@
$new=@'
<div className="toolbar cashier-toolbar-top"><h2>{showTrash?'Sampah pesanan':'Antrean pesanan'}</h2><div className="cashier-view-tabs"><button type="button" className={!showTrash?'active':''} onClick={()=>setShowTrash(false)}>Antrean aktif ({orders.length})</button><button type="button" className={showTrash?'active':''} onClick={()=>setShowTrash(true)}>Sampah ({trashOrders.length})</button></div></div><div className="cashier-filters">{!showTrash&&<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Cari nama, tiket, asrama..."/>
'@
$old=$old.TrimEnd([char[]]@(10,13))
$new=$new.TrimEnd([char[]]@(10,13))
$app=Replace-Once $app $old $new 'layout toolbar kasir'
$old=@'
{!showTrash&&<select aria-label="Filter status pesanan" value={filter} onChange={e=>setFilter(e.target.value)}><option>Semua</option><option>Menunggu</option><option>Dikonfirmasi</option><option>Diproses</option><option>Siap diserahkan</option><option>Sudah diserahkan</option><option>Dibatalkan</option></select>}
'@
$new=@'
{!showTrash&&<label className="cashier-date-filter">Dari tanggal pemesanan<input type="date" value={cashierOrderFrom} max={cashierOrderTo || undefined} onChange={e=>setCashierOrderFrom(e.target.value)}/></label>}{!showTrash&&<label className="cashier-date-filter">Sampai tanggal pemesanan<input type="date" value={cashierOrderTo} min={cashierOrderFrom || undefined} onChange={e=>setCashierOrderTo(e.target.value)}/></label>}{!showTrash&&invalidCashierOrderRange&&<span className="fine-print cashier-date-warning">Tanggal mulai tidak boleh melewati tanggal akhir.</span>}
'@
$old=$old.TrimEnd([char[]]@(10,13))
$new=$new.TrimEnd([char[]]@(10,13))
$app=Replace-Once $app $old $new 'tanggal pemesanan menggantikan filter status'
$app=Replace-Once $app '`Menampilkan ${orders.length} pesanan terbaru menurut waktu pemesanan.`' '`Menampilkan ${filteredOrders.length} dari ${orders.length} pesanan yang dimuat.`' 'keterangan jumlah hasil'
$brokenDash=([string][char]0x00E2)+[char]0x20AC+[char]0x201D
$correctDash=[string][char]0x2013
$count=[regex]::Matches($app,[regex]::Escape($brokenDash)).Count
if($count -ne 2){throw "Teks encoding rusak ditemukan $count kali; seharusnya 2. Tidak ada file yang ditulis."}
$app=$app.Replace($brokenDash,$correctDash)
$css += @'

/* WDI: rentang tanggal pemesanan pada antrean Kasir */
.cashier-toolbar-top{margin-bottom:10px}
.cashier-filters{display:grid;grid-template-columns:minmax(190px,1.35fr) minmax(155px,.9fr) repeat(2,minmax(160px,.85fr)) auto;gap:12px;align-items:end;margin:0 0 16px}
.cashier-date-filter,.cashier-filters .cashier-gender-filter{min-width:0}
.cashier-date-warning{grid-column:1/-1}
.cashier-filters>button{align-self:end;min-height:44px}
@media(max-width:1000px){.cashier-filters{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:600px){.cashier-toolbar-top{align-items:flex-start}.cashier-filters{grid-template-columns:1fr}.cashier-date-warning{grid-column:auto}}
'@
Copy-Item $appPath "$appPath.before-date-filter-update" -Force
Copy-Item $cssPath "$cssPath.before-date-filter-update" -Force
$utf8NoBom=New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($appPath,$app,$utf8NoBom)
[IO.File]::WriteAllText($cssPath,$css,$utf8NoBom)
Write-Host ''
Write-Host 'Perbaikan encoding dan filter tanggal Kasir berhasil diterapkan.' -ForegroundColor Green
Write-Host "Backup App.jsx : $appPath.before-date-filter-update"
Write-Host "Backup CSS     : $cssPath.before-date-filter-update"
Write-Host 'Jalankan npm run build untuk memeriksa hasil kompilasi.'

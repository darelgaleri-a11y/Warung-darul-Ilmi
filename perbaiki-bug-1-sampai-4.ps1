$ErrorActionPreference = 'Stop'

$projectRoot = (Get-Location).Path
$appPath = Join-Path $projectRoot 'src\App.jsx'
if (-not (Test-Path -LiteralPath $appPath)) {
    throw 'src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek Warung Darul Ilmi.'
}

$original = [System.IO.File]::ReadAllText($appPath)
$lineEnding = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
$text = $original.Replace("`r`n", "`n").Replace("`r", "`n")

function Replace-Section {
    param(
        [string]$Text,
        [string]$StartMarker,
        [string]$EndMarker,
        [string]$Replacement,
        [string]$Description
    )
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Bagian '$Description' tidak ditemukan. File tidak cocok dengan versi yang diharapkan." }
    $secondStart = $Text.IndexOf($StartMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($secondStart -ge 0) { throw "Penanda awal '$Description' ditemukan lebih dari sekali. Perubahan dibatalkan." }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { throw "Penanda akhir '$Description' tidak ditemukan. File tidak cocok dengan versi yang diharapkan." }
    return $Text.Substring(0, $start) + $Replacement + $Text.Substring($end)
}

function Replace-Once {
    param([string]$Text, [string]$Old, [string]$New, [string]$Description)
    $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Bagian '$Description' tidak ditemukan. Perubahan dibatalkan." }
    $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Bagian '$Description' ditemukan lebih dari sekali. Perubahan dibatalkan." }
    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

# 1) Tambahkan ref/state pendukung untuk mencegah permintaan yang bertumpuk dan memisahkan data antrean, laporan, serta distribusi.
$text = Replace-Once $text "import { useEffect, useMemo, useState } from 'react';" "import { useEffect, useMemo, useRef, useState } from 'react';" 'import useRef'
$newOrderStates = @'
  const [orders, setOrders] = useState([]);
  const [ordersRealtimeVersion, setOrdersRealtimeVersion] = useState(0);
  const [ordersHasMore, setOrdersHasMore] = useState(false);
  const [ordersLoadingMore, setOrdersLoadingMore] = useState(false);
  const [reportOrders, setReportOrders] = useState([]);
  const [reportLoading, setReportLoading] = useState(false);
  const [reportLoaded, setReportLoaded] = useState(false);
  const [reportLimitReached, setReportLimitReached] = useState(false);
  const [distributionRows, setDistributionRows] = useState([]);
  const [distributionLoading, setDistributionLoading] = useState(false);
  const [distributionLimitReached, setDistributionLimitReached] = useState(false);
'@
$text = Replace-Once $text "  const [orders, setOrders] = useState([]);`n" $newOrderStates 'state antrean/laporan/distribusi'
$newDistributionState = @'
  const [distributionGender, setDistributionGender] = useState('Semua');
'@
$text = Replace-Once $text "  const [distributionGender, setDistributionGender] = useState('Semua');`n" $newDistributionState 'state distribusi'
$newRequestRefs = @'
  const ordersLoadInFlightRef = useRef(false);
  const ordersRefreshQueuedRef = useRef(false);
  const distributionLoadVersionRef = useRef(0);
  const reportLoadInFlightRef = useRef(false);
  const isStaff = ['cashier','super_admin'].includes(profile?.role);
'@
$text = Replace-Once $text "  const isStaff = ['cashier','super_admin'].includes(profile?.role);" $newRequestRefs 'ref pengendali permintaan'

# 2) Koneksi hanya dianggap siap bila kelima sumber penting berhasil dibaca dan tanggal pengiriman valid.
$startupStart = "  useEffect(() => {`n    let alive = true;`n    if (!supabase) { setDatabaseStatus('missing-config'); setMenuLoading(false); return undefined; }"
$profileStart = "  useEffect(() => {`n    let alive = true;`n    async function loadProfile()"
$startup = @'
  useEffect(() => {
    let alive = true;
    if (!supabase) { setDatabaseStatus('missing-config'); setMenuLoading(false); return undefined; }
    setDatabaseStatus('checking');
    setMenuLoading(true);

    const run = async (label, request, onSuccess) => {
      try {
        const result = await request;
        if (!alive) return false;
        if (result?.error) {
          console.warn(`Gagal memuat ${label}:`, result.error);
          return false;
        }
        return onSuccess(result) !== false;
      } catch (error) {
        if (alive) console.warn(`Gagal memuat ${label}:`, error);
        return false;
      }
    };

    const tasks = [
      run('pengaturan toko', supabase.from('store_settings').select('*').eq('id', true).maybeSingle(), ({ data }) => {
        if (!data || typeof data !== 'object') return false;
        setStoreSettings(current => ({ ...current, ...data }));
        return true;
      }),
      run('kategori', supabase.from('categories').select('id,name,sort_order').eq('is_active', true).order('sort_order'), ({ data }) => {
        if (!Array.isArray(data)) return false;
        setCategories(['Semua', ...data.map(c => c.name)]);
        return true;
      }),
      run('produk', supabase.from('products').select('id,name,description,price,image_url,category_id,categories(name)').eq('is_available', true).order('name'), ({ data }) => {
        if (!Array.isArray(data)) return false;
        setProducts(data.map(p => ({ id: p.id, name: p.name, description: p.description || '', price: Number(p.price), image: p.image_url, category: p.categories?.name || 'Lainnya', emoji: String.fromCodePoint(0x1F37D) })));
        return true;
      }),
      run('jadwal mingguan', supabase.from('delivery_weekdays').select('weekday,is_active').order('weekday'), ({ data }) => {
        if (!Array.isArray(data)) return false;
        setDeliveryWeekdays(data);
        return true;
      }),
      run('tanggal pengiriman berikutnya', supabase.rpc('next_delivery_date'), ({ data }) => {
        const validDate = typeof data === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(data)
          && !Number.isNaN(Date.parse(`${data}T00:00:00Z`))
          && new Date(`${data}T00:00:00Z`).toISOString().slice(0, 10) === data;
        if (!validDate) return false;
        setNextDeliveryDate(data);
        return true;
      })
    ];

    Promise.all(tasks).then(results => {
      if (!alive) return;
      const allRequiredDataReady = results.every(Boolean);
      setDatabaseStatus(allRequiredDataReady ? 'connected' : 'error');
      if (allRequiredDataReady) {
        setNotice('Terhubung ke Supabase. Produk, pengaturan toko, dan jadwal pengiriman siap digunakan.');
      } else {
        setNotice('Database belum siap untuk checkout. Sebagian data wajib gagal dimuat atau jadwal pengiriman berikutnya belum tersedia. Periksa tabel, jadwal, dan koneksi Supabase.');
      }
    }).finally(() => {
      if (alive) setMenuLoading(false);
    });

    return () => { alive = false; };
  }, []);

'@
$text = Replace-Section $text $startupStart $profileStart $startup 'pemeriksaan kesiapan database'

# 3) Operasi katalog: exception ditangani, hasil tulis diverifikasi, dan busy flag selalu dipulihkan.
$catalogStart = '  async function loadAdminCatalog() {'
$catalogEnd = '  useEffect(() => { if (isAdmin && page === ''catalog'') loadAdminCatalog(); }, [isAdmin, page]);'
$catalogCode = @'
  async function loadAdminCatalog({manageBusy = true} = {}) {
    if (!supabase || !isAdmin) return false;
    if (manageBusy) setCatalogBusy(true);
    try {
      const [{ data: cats, error: catError }, { data: prods, error: prodError }] = await Promise.all([
        supabase.from('categories').select('id,name,sort_order,is_active').order('sort_order').order('name'),
        supabase.from('products').select('id,name,description,sku,price,image_url,category_id,is_available,categories(name)').order('name')
      ]);
      if (catError) throw catError;
      if (prodError) throw prodError;
      if (!Array.isArray(cats) || !Array.isArray(prods)) throw new Error('Server tidak mengembalikan daftar kategori dan produk yang valid.');
      setAdminCategories(cats);
      setAdminProducts(prods);
      return true;
    } catch (error) {
      setNotice(`Gagal memuat katalog admin: ${error?.message || 'Kesalahan jaringan.'}`);
      return false;
    } finally {
      if (manageBusy) setCatalogBusy(false);
    }
  }
  function resetProductForm() {
    setProductForm({id:null,name:'',description:'',price:'',category_id:adminCategories.find(c=>c.is_active)?.id || '',image_url:'',sku:'',is_available:true});
    setEditingProduct(false);
  }
  function editProduct(product) {
    setProductForm({id:product.id,name:product.name,description:product.description||'',price:String(product.price),category_id:product.category_id||'',image_url:product.image_url||'',sku:product.sku||'',is_available:product.is_available});
    setEditingProduct(true);
    window.scrollTo({top:0,behavior:'smooth'});
  }
  async function saveProduct(e) {
    e.preventDefault();
    if (!supabase || !isAdmin) return;
    const price = Number(productForm.price);
    if (!productForm.name.trim() || !Number.isSafeInteger(price) || price < 0) {
      setNotice('Nama produk wajib diisi dan harga harus berupa angka bulat minimal 0.');
      return;
    }
    setCatalogBusy(true);
    let writeConfirmed = false;
    try {
      const payload = {name:productForm.name.trim(),description:productForm.description.trim()||null,price,category_id:productForm.category_id?Number(productForm.category_id):null,image_url:productForm.image_url.trim()||null,sku:productForm.sku.trim()||null,is_available:productForm.is_available,updated_at:new Date().toISOString()};
      const query = productForm.id
        ? supabase.from('products').update(payload).eq('id',productForm.id)
        : supabase.from('products').insert(payload);
      const {data,error} = await query.select('id').maybeSingle();
      if (error) throw error;
      if (!data?.id) throw new Error('Database tidak mengonfirmasi baris produk yang disimpan.');
      writeConfirmed = true;
      resetProductForm();
      const adminRefreshOk = await loadAdminCatalog({manageBusy:false});
      let customerRefreshOk = true;
      try { await refreshCustomerCatalog(); } catch (refreshError) { customerRefreshOk = false; throw refreshError; }
      if (!adminRefreshOk || !customerRefreshOk) setNotice('Produk tersimpan, tetapi daftar katalog belum berhasil dimuat ulang. Tekan Muat ulang untuk memperbarui tampilan.');
      else setNotice(productForm.id?'Produk berhasil diperbarui dan diverifikasi.':'Produk berhasil ditambahkan dan diverifikasi.');
    } catch (error) {
      setNotice(writeConfirmed ? `Produk tersimpan, tetapi tampilan katalog gagal diperbarui: ${error?.message || 'Kesalahan jaringan.'}. Tekan Muat ulang.` : `Produk gagal dipastikan tersimpan: ${error?.message || 'Kesalahan jaringan.'}. Data formulir tetap dipertahankan.`);
    } finally {
      setCatalogBusy(false);
    }
  }
  async function refreshCustomerCatalog() {
    if (!supabase) throw new Error('Supabase belum dikonfigurasi.');
    const [{data: cats, error: catError}, {data: prods, error: prodError}] = await Promise.all([
      supabase.from('categories').select('id,name,sort_order').eq('is_active',true).order('sort_order'),
      supabase.from('products').select('id,name,description,price,image_url,category_id,categories(name)').eq('is_available',true).order('name')
    ]);
    if (catError) throw catError;
    if (prodError) throw prodError;
    if (!Array.isArray(cats) || !Array.isArray(prods)) throw new Error('Data katalog pelanggan tidak valid.');
    setCategories(['Semua',...cats.map(c=>c.name)]);
    setProducts(prods.map(p=>({id:p.id,name:p.name,description:p.description||'',price:Number(p.price),image:p.image_url,category:p.categories?.name||'Lainnya',emoji:'🍽️'})));
  }
  async function addCategory(e) {
    e.preventDefault();
    if (!supabase || !isAdmin) return;
    const name = categoryName.trim();
    if (!name) return;
    setCatalogBusy(true);
    let writeConfirmed = false;
    try {
      const {data,error} = await supabase.from('categories').insert({name,sort_order:adminCategories.length,is_active:true}).select('id').maybeSingle();
      if (error) throw error;
      if (!data?.id) throw new Error('Database tidak mengonfirmasi kategori yang ditambahkan.');
      writeConfirmed = true;
      setCategoryName('');
      const adminRefreshOk = await loadAdminCatalog({manageBusy:false});
      try { await refreshCustomerCatalog(); } catch (refreshError) { setNotice(`Kategori tersimpan, tetapi katalog pelanggan gagal dimuat ulang: ${refreshError?.message || 'Kesalahan jaringan.'}.`); return; }
      setNotice(adminRefreshOk ? 'Kategori berhasil ditambahkan dan diverifikasi.' : 'Kategori tersimpan, tetapi daftar admin belum berhasil dimuat ulang. Tekan Muat ulang.');
    } catch (error) {
      setNotice(writeConfirmed ? `Kategori tersimpan, tetapi tampilan gagal diperbarui: ${error?.message || 'Kesalahan jaringan.'}. Tekan Muat ulang.` : `Kategori gagal disimpan: ${error?.message || 'Kesalahan jaringan.'}`);
    } finally {
      setCatalogBusy(false);
    }
  }
  async function toggleCategory(cat) {
    if (!supabase || !isAdmin) return;
    setCatalogBusy(true);
    let writeConfirmed = false;
    try {
      const nextValue = !cat.is_active;
      const {data,error} = await supabase.from('categories').update({is_active:nextValue}).eq('id',cat.id).select('id,is_active').maybeSingle();
      if (error) throw error;
      if (!data || data.id !== cat.id || data.is_active !== nextValue) throw new Error('Perubahan kategori tidak ditemukan pada hasil verifikasi database.');
      writeConfirmed = true;
      const adminRefreshOk = await loadAdminCatalog({manageBusy:false});
      try { await refreshCustomerCatalog(); } catch (refreshError) { setNotice(`Kategori sudah tersimpan, tetapi katalog pelanggan gagal dimuat ulang: ${refreshError?.message || 'Kesalahan jaringan.'}.`); return; }
      setNotice(adminRefreshOk ? `Kategori ${nextValue?'diaktifkan':'dinonaktifkan'} dan telah diverifikasi.` : 'Kategori tersimpan, tetapi daftar admin belum berhasil dimuat ulang. Tekan Muat ulang.');
    } catch (error) {
      setNotice(writeConfirmed ? `Kategori tersimpan, tetapi tampilan gagal diperbarui: ${error?.message || 'Kesalahan jaringan.'}.` : `Kategori gagal diperbarui: ${error?.message || 'Kesalahan jaringan.'}`);
    } finally {
      setCatalogBusy(false);
    }
  }
  async function toggleProductAvailability(product) {
    if (!supabase || !isAdmin) return;
    setCatalogBusy(true);
    let writeConfirmed = false;
    try {
      const nextValue = !product.is_available;
      const {data,error} = await supabase.from('products').update({is_available:nextValue,updated_at:new Date().toISOString()}).eq('id',product.id).select('id,is_available').maybeSingle();
      if (error) throw error;
      if (!data || data.id !== product.id || data.is_available !== nextValue) throw new Error('Perubahan ketersediaan produk tidak terkonfirmasi dari database.');
      writeConfirmed = true;
      const adminRefreshOk = await loadAdminCatalog({manageBusy:false});
      try { await refreshCustomerCatalog(); } catch (refreshError) { setNotice(`Status produk sudah tersimpan, tetapi katalog pelanggan gagal dimuat ulang: ${refreshError?.message || 'Kesalahan jaringan.'}.`); return; }
      setNotice(adminRefreshOk ? `Produk berhasil ${nextValue?'ditampilkan':'disembunyikan'} dan telah diverifikasi.` : 'Produk tersimpan, tetapi daftar admin belum berhasil dimuat ulang. Tekan Muat ulang.');
    } catch (error) {
      setNotice(writeConfirmed ? `Perubahan produk tersimpan, tetapi tampilan gagal diperbarui: ${error?.message || 'Kesalahan jaringan.'}.` : `Status produk gagal diperbarui: ${error?.message || 'Kesalahan jaringan.'}`);
    } finally {
      setCatalogBusy(false);
    }
  }
'@
$text = Replace-Section $text $catalogStart $catalogEnd $catalogCode 'operasi katalog'

# 4) Antrean memakai 100 data terbaru per halaman. Realtime didebounce dan refresh saat request berjalan hanya diantrekan sekali.
$ordersStart = '  async function loadOrders() {'
$ordersEnd = '  const cartCount = cart.reduce'
$ordersCode = @'
  async function loadOrders({append = false} = {}) {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return;
    if (ordersLoadInFlightRef.current) return;
    if (profile.role === 'cashier' && !normalizeGender(profile.cashier_gender)) {
      setOrders([]);
      setOrdersHasMore(false);
      setNotice('Akun kasir belum diberi jalur Putra atau Putri. Minta Super Admin mengatur cashier_gender pada profil akun ini.');
      return;
    }

    const PAGE_SIZE = 100;
    const from = append ? orders.length : 0;
    ordersLoadInFlightRef.current = true;
    if (append) setOrdersLoadingMore(true); else setLoadingOrders(true);
    try {
      let query = supabase.from('orders')
        .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
        .order('created_at',{ascending:false})
        .order('id',{ascending:false})
        .range(from, from + PAGE_SIZE - 1);
      if (profile.role === 'cashier') query = query.eq('guest_gender', normalizeGender(profile.cashier_gender));
      const {data,error} = await query;
      if (error) throw error;
      const pageRows = Array.isArray(data) ? data.map(mapOrder) : [];
      if (append) {
        setOrders(current => {
          const seen = new Set(current.map(order => order.id));
          return [...current, ...pageRows.filter(order => !seen.has(order.id))];
        });
      } else {
        setOrders(pageRows);
      }
      setOrdersHasMore((data || []).length === PAGE_SIZE);
    } catch (error) {
      setNotice(`Gagal memuat pesanan: ${error?.message || 'Kesalahan jaringan.'}. Data antrean sebelumnya dipertahankan.`);
    } finally {
      ordersLoadInFlightRef.current = false;
      setLoadingOrders(false);
      setOrdersLoadingMore(false);
      if (ordersRefreshQueuedRef.current) {
        ordersRefreshQueuedRef.current = false;
        window.setTimeout(() => loadOrders(), 150);
      }
    }
  }
  useEffect(() => { loadOrders(); }, [profile?.id, profile?.role, profile?.cashier_gender]);
  useEffect(() => {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return undefined;
    let refreshTimer = null;
    const queueRefresh = () => {
      if (refreshTimer) window.clearTimeout(refreshTimer);
      refreshTimer = window.setTimeout(() => {
        refreshTimer = null;
        if (ordersLoadInFlightRef.current) ordersRefreshQueuedRef.current = true;
        else loadOrders();
        setOrdersRealtimeVersion(version => version + 1);
      }, 400);
    };
    const channel = supabase.channel('wdi-orders-live')
      .on('postgres_changes',{event:'*',schema:'public',table:'orders'},queueRefresh)
      .subscribe();
    return () => {
      if (refreshTimer) window.clearTimeout(refreshTimer);
      supabase.removeChannel(channel);
    };
  }, [profile?.id, profile?.role, profile?.cashier_gender, page]);

'@
$text = Replace-Section $text $ordersStart $ordersEnd $ordersCode 'pemuatan antrean dan realtime'

# 5) Laporan berdasarkan rentang tanggal; distribusi mengambil data khusus tanggal pengiriman agar tidak terpotong antrean terbaru.
$derivedStart = '  const distributionOrders = scopedOrders.filter(o => o.deliveryDate === effectiveDistributionDate'
$cashierAccountsStart = '  async function loadCashierAccounts() {'
$derivedCode = @'
  const distributionOrders = distributionRows.filter(o => !effectiveDistributionGender || effectiveDistributionGender === 'Semua' || o.customer.gender === effectiveDistributionGender);
  const distributionGroups = Object.values(distributionOrders.reduce((acc, order) => { const key = `${order.customer.gender} · ${order.customer.dorm || 'Tanpa asrama'}`; (acc[key] ||= []).push(order); return acc; }, {})).sort((a,b) => `${a[0].customer.gender}-${a[0].customer.dorm}`.localeCompare(`${b[0].customer.gender}-${b[0].customer.dorm}`,'id'));
  const invalidReportRange = Boolean(reportFrom && reportTo && reportFrom > reportTo);

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

  async function loadReportOrders() {
    if (!supabase || !isAdmin || reportLoadInFlightRef.current) return;
    if (!reportFrom && !reportTo) {
      setReportLoaded(false);
      setNotice('Pilih minimal satu batas tanggal pengiriman agar laporan mengambil data sesuai periode, bukan seluruh riwayat sekaligus.');
      return;
    }
    if (invalidReportRange) {
      setReportLoaded(false);
      setNotice('Tanggal mulai tidak boleh melewati tanggal akhir.');
      return;
    }
    const PAGE_SIZE = 500;
    const MAX_ROWS = 50000;
    let allRows = [];
    let reachedLimit = false;
    reportLoadInFlightRef.current = true;
    setReportLoading(true);
    setReportLoaded(false);
    setReportLimitReached(false);
    setReportOrders([]);
    try {
      for (let from = 0; from < MAX_ROWS; from += PAGE_SIZE) {
        let query = supabase.from('orders')
          .select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)')
          .order('created_at',{ascending:false})
          .order('id',{ascending:false})
          .range(from, from + PAGE_SIZE - 1);
        if (reportFrom) query = query.gte('delivery_date', reportFrom);
        if (reportTo) query = query.lte('delivery_date', reportTo);
        if (reportGender !== 'Semua') query = query.eq('guest_gender', reportGender);
        const {data,error} = await query;
        if (error) throw error;
        const rows = Array.isArray(data) ? data : [];
        allRows = allRows.concat(rows);
        if (rows.length < PAGE_SIZE) break;
        if (from + PAGE_SIZE >= MAX_ROWS) reachedLimit = true;
      }
      setReportOrders(allRows.map(mapOrder));
      setReportLimitReached(reachedLimit);
      setReportLoaded(true);
      if (reachedLimit) setNotice('Laporan mencapai batas aman 50.000 transaksi. Persempit rentang tanggal sebelum mengekspor agar laporan tidak terpotong.');
      else setNotice(`Laporan berhasil dimuat: ${allRows.length} transaksi.`);
    } catch (error) {
      setReportOrders([]);
      setReportLoaded(false);
      setNotice(`Gagal memuat laporan: ${error?.message || 'Kesalahan jaringan.'}`);
    } finally {
      reportLoadInFlightRef.current = false;
      setReportLoading(false);
    }
  }
'@
$text = Replace-Section $text $derivedStart $cashierAccountsStart $derivedCode 'laporan dan distribusi berbasis tanggal'

# 6) Update status dapat menargetkan baris dari data laporan/distribusi yang tidak berada di 100 antrean terbaru.
$text = Replace-Once $text "    const target = orders.find(o => o.id === id);" "    const target = orders.find(o => o.id === id) || reportOrders.find(o => o.id === id) || distributionRows.find(o => o.id === id);" 'pencarian pesanan untuk updateOrder'
$newOrderRefresh = @'
      setNotice('Perubahan pesanan tersimpan dan telah diverifikasi dari database.');
      await loadOrders();
      if (page === 'reports' && reportLoaded) await loadReportOrders();
      if (page === 'distribution') await loadDistributionOrders(effectiveDistributionDate);
'@
$text = Replace-Once $text "      setNotice('Perubahan pesanan tersimpan dan telah diverifikasi dari database.');`n      await loadOrders();" $newOrderRefresh 'refresh setelah updateOrder'

# 7) Ekspor hanya diperbolehkan setelah laporan yang sesuai filter selesai dimuat secara lengkap.
$newReportExportGuard = @'
    if (reportLoading || !reportLoaded) { setNotice('Muat laporan berdasarkan rentang tanggal terlebih dahulu sebelum mengekspor.'); return; }
    if (reportLimitReached) { setNotice('Laporan belum lengkap karena mencapai batas 50.000 transaksi. Persempit rentang tanggal sebelum mengekspor.'); return; }
    if (!reportOrders.length) { setNotice('Tidak ada pesanan pada rentang tanggal pengiriman yang dipilih.'); return; }
'@
$text = Replace-Once $text "    if (!reportOrders.length) { setNotice('Tidak ada pesanan pada rentang tanggal pengiriman yang dipilih.'); return; }" $newReportExportGuard 'validasi ekspor laporan'

# 8) UI antrean memuat halaman tambahan, laporan harus diminta secara eksplisit, dan distribusi menunjukkan status pemuatan.
$newQueuePagination = @'
<OrderList orders={filteredOrders} onStatus={(id,v)=>updateOrder(id,{status:v})}/><div className="toolbar"><span className="muted">Menampilkan {orders.length} pesanan terbaru yang sudah dimuat.</span>{ordersHasMore&&<button type="button" onClick={()=>loadOrders({append:true})} disabled={loadingOrders||ordersLoadingMore}>{ordersLoadingMore?'Memuat...':'Muat 100 pesanan berikutnya'}</button>}</div></section>}
'@
$text = Replace-Once $text "<OrderList orders={filteredOrders} onStatus={(id,v)=>updateOrder(id,{status:v})}/></section>}" $newQueuePagination 'tombol halaman berikutnya antrean'
$text = Replace-Once $text '<div className="stats"><div className="stat-card"><small>Jumlah pesanan</small>' '<div className="stats"><div className="stat-card"><small>Pesanan pada tanggal ini</small>' 'label jumlah distribusi'
$text = Replace-Once $text '</div><div className="stats"><div className="stat-card"><small>Pesanan pada tanggal ini</small>' '</div>{distributionLoading&&<p className="muted">Memuat semua pesanan pada tanggal distribusi...</p>}{distributionLimitReached&&<p className="notice">Daftar tanggal ini mencapai batas pemuatan.</p>}<div className="stats"><div className="stat-card"><small>Pesanan pada tanggal ini</small>' 'indikator pemuatan distribusi'
$oldReportControls = @'
<button type="button" onClick={()=>{setReportFrom('');setReportTo('');setReportGender('Semua');}}>Reset filter</button><button type="button" onClick={loadOrders}>Muat ulang</button><button className="primary" type="button" onClick={exportWorkbook}>Unduh Excel (.xlsx)</button>
'@
$oldReportControls = $oldReportControls.Trim()
$newReportControls = @'
<button type="button" onClick={()=>{setReportFrom('');setReportTo('');setReportGender('Semua');setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}} disabled={reportLoading}>Reset filter</button><button type="button" onClick={loadReportOrders} disabled={reportLoading}>{reportLoading?'Memuat laporan...':'Tampilkan / muat ulang laporan'}</button><button className="primary" type="button" onClick={exportWorkbook} disabled={reportLoading||!reportLoaded||reportLimitReached}>Unduh Excel (.xlsx)</button>
'@
$text = Replace-Once $text $oldReportControls $newReportControls 'kontrol pemuatan laporan'
$text = Replace-Once $text "onChange={e=>setReportFrom(e.target.value)}" "onChange={e=>{setReportFrom(e.target.value);setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}}" 'reset hasil saat filter tanggal mulai berubah'
$text = Replace-Once $text "onChange={e=>setReportTo(e.target.value)}" "onChange={e=>{setReportTo(e.target.value);setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}}" 'reset hasil saat filter tanggal akhir berubah'
$text = Replace-Once $text "onChange={e=>setReportGender(e.target.value)}" "onChange={e=>{setReportGender(e.target.value);setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}}" 'reset hasil saat filter kategori berubah'
$text = Replace-Once $text 'value={reportFrom} onChange=' 'value={reportFrom} disabled={reportLoading} onChange=' 'kunci filter tanggal mulai saat memuat laporan'
$text = Replace-Once $text 'value={reportTo} min={reportFrom||undefined} onChange=' 'value={reportTo} min={reportFrom||undefined} disabled={reportLoading} onChange=' 'kunci filter tanggal akhir saat memuat laporan'
$text = Replace-Once $text 'value={reportGender} onChange=' 'value={reportGender} disabled={reportLoading} onChange=' 'kunci filter kategori saat memuat laporan'
$oldReportResults = @'
{invalidReportRange?<div className="panel empty">Tanggal mulai tidak boleh melewati tanggal akhir.</div>:<OrderList orders={reportOrders} onStatus={(id,v)=>updateOrder(id,{status:v})}/>}
'@
$newReportResults = @'
{invalidReportRange?<div className="panel empty">Tanggal mulai tidak boleh melewati tanggal akhir.</div>:reportLoading?<div className="panel empty">Memuat laporan sesuai rentang tanggal...</div>:!reportLoaded?<div className="panel empty">Pilih minimal satu tanggal, lalu tekan Tampilkan / muat ulang laporan. Riwayat tidak diunduh seluruhnya saat halaman dibuka.</div>:<OrderList orders={reportOrders} onStatus={(id,v)=>updateOrder(id,{status:v})}/>}
'@
$text = Replace-Once $text $oldReportResults $newReportResults 'tampilan status laporan'

# Angka dashboard hanya merepresentasikan pesanan yang sedang dimuat (bukan seluruh riwayat).
$text = Replace-Once $text '<small>Jumlah transaksi</small><strong>{orders.length}</strong>' '<small>Pesanan terbaru dimuat</small><strong>{orders.length}</strong>' 'label statistik dashboard jumlah'
$text = Replace-Once $text '<small>Nilai seluruh pesanan</small><strong>{money(orders.reduce((s,o)=>s+o.total,0))}</strong>' '<small>Nilai pesanan terbaru dimuat</small><strong>{money(orders.reduce((s,o)=>s+o.total,0))}</strong>' 'label statistik dashboard nilai'
$text = Replace-Once $text "<small>Pesanan belum selesai</small><strong>{orders.filter(o=>!['delivered','cancelled'].includes(o.status)).length}</strong>" "<small>Belum selesai (pesanan dimuat)</small><strong>{orders.filter(o=>!['delivered','cancelled'].includes(o.status)).length}</strong>" 'label statistik dashboard belum selesai'

# Jelaskan bahwa angka kasir juga dihitung dari pesanan yang saat ini sudah dimuat.
$text = Replace-Once $text '<small>Menunggu konfirmasi</small>' '<small>Menunggu (pesanan dimuat)</small>' 'label kasir menunggu'
$text = Replace-Once $text '<small>Sedang diproses</small>' '<small>Diproses (pesanan dimuat)</small>' 'label kasir diproses'
$text = Replace-Once $text '<small>Siap diserahkan</small>' '<small>Siap diserahkan (pesanan dimuat)</small>' 'label kasir siap'

# Periksa bahwa fitur sebelumnya (checkout dan validasi update status) tidak hilang.
$required = @(
    'setWhatsAppFallbackUrl(whatsappUrl)',
    'whatsappTab.location.replace(whatsappUrl)',
    ".select('id,status')",
    'setCart([])',
    'async function loadReportOrders()',
    'Muat 100 pesanan berikutnya'
)
foreach ($marker in $required) {
    if (-not $text.Contains($marker)) { throw "Pemeriksaan akhir gagal: fitur penting '$marker' tidak ditemukan. File asli tidak diubah." }
}

# Pulihkan line ending asli dan simpan dengan backup. File lama tidak ditimpa sebelum seluruh pemeriksaan lolos.
$backupPath = Join-Path (Split-Path $appPath -Parent) ('App.jsx.bak-sebelum-perbaikan-1-4-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
[System.IO.File]::Copy($appPath, $backupPath, $false)
$finalText = $text.Replace("`n", $lineEnding)
try {
    [System.IO.File]::WriteAllText($appPath, $finalText, (New-Object System.Text.UTF8Encoding($false)))
    $written = [System.IO.File]::ReadAllText($appPath)
    foreach ($marker in $required) {
        if (-not $written.Contains($marker)) { throw "Verifikasi file setelah penulisan gagal pada '$marker'." }
    }
} catch {
    [System.IO.File]::Copy($backupPath, $appPath, $true)
    throw "Penulisan gagal; App.jsx dipulihkan dari backup. Detail: $($_.Exception.Message)"
}

Write-Host ''
Write-Host 'Perbaikan bug 1-4 berhasil diterapkan pada src\App.jsx.' -ForegroundColor Green
Write-Host "Backup: $backupPath"
Write-Host 'Langkah berikutnya: jalankan npm run build.'

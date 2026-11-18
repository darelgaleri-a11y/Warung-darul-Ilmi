import { useEffect, useMemo, useState } from 'react';
import { isSupabaseConfigured, supabase } from './lib/supabase.js';
import * as XLSX from 'xlsx';

const money = value => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(Number(value || 0));
const statusLabels = { pending: 'Menunggu', confirmed: 'Dikonfirmasi', preparing: 'Diproses', ready: 'Siap diserahkan', delivered: 'Sudah diserahkan', cancelled: 'Dibatalkan' };
const statusValues = Object.fromEntries(Object.entries(statusLabels).map(([k,v]) => [v,k]));
const fallbackMenu = [
  { id: 1, name: 'Nasi Ayam', category: 'Makanan', price: 12000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '🍗' },
  { id: 2, name: 'Nasi Goreng', category: 'Makanan', price: 10000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '🍛' },
  { id: 3, name: 'Mie Goreng', category: 'Makanan', price: 9000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '🍜' },
  { id: 4, name: 'Es Teh', category: 'Minuman', price: 4000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '🧋' },
  { id: 5, name: 'Air Mineral', category: 'Minuman', price: 3000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '💧' },
  { id: 6, name: 'Roti Cokelat', category: 'Camilan', price: 5000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '🥐' }
];
function normalizeGender(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'putra') return 'Putra';
  if (normalized === 'putri') return 'Putri';
  return '';
}
function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>\"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[char]));
}
function mapOrder(row) {
  const items = (row.order_items || []).map(x => ({ id: x.product_id ?? x.id, name: x.product_name_snapshot, price: Number(x.unit_price_snapshot), qty: x.quantity }));
  return { id: row.id, number: row.order_number, createdAt: row.created_at, deliveryDate: row.delivery_date,
    customer: { name: row.guest_name || row.profiles?.full_name || 'Pelanggan', gender: normalizeGender(row.guest_gender), dorm: row.guest_dormitory || '-', className: row.guest_class || '-', phone: row.guest_phone || '' },
    note: row.customer_note || '', items, total: Number(row.total_amount || 0), status: row.status };
}
function App() {
  const [page, setPage] = useState('order');
  const [products, setProducts] = useState(fallbackMenu);
  const [categories, setCategories] = useState(['Semua','Makanan','Minuman','Camilan']);
  const [cart, setCart] = useState([]);
  const [category, setCategory] = useState('Semua');
  const [identity, setIdentity] = useState({ name: '', gender: 'Putra', dorm: '', className: '', phone: '', note: '' });
  const [notice, setNotice] = useState('');
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [staffLoginOpen, setStaffLoginOpen] = useState(false);
  const [databaseStatus, setDatabaseStatus] = useState(isSupabaseConfigured ? 'checking' : 'missing-config');
  const [orders, setOrders] = useState([]);
  const [filter, setFilter] = useState('Semua');
  const [search, setSearch] = useState('');
  const [loadingOrders, setLoadingOrders] = useState(false);
  const [storeSettings, setStoreSettings] = useState({ store_name: 'Warung Darul Ilmi', whatsapp_number: '', whatsapp_number_putra: '', whatsapp_number_putri: '', bank_name: '', bank_account_number: '', bank_account_name: '' });
  const [settingsBusy, setSettingsBusy] = useState(false);
  const [menuLoading, setMenuLoading] = useState(false);
  const [deliveryWeekdays, setDeliveryWeekdays] = useState([]);
  const [nextDeliveryDate, setNextDeliveryDate] = useState(null);
  const [scheduleBusy, setScheduleBusy] = useState(false);
  const [dateOverrides, setDateOverrides] = useState([]);
  const [overrideDate, setOverrideDate] = useState('');
  const [overrideDelivery, setOverrideDelivery] = useState(false);
  const [overrideNote, setOverrideNote] = useState('');
  const [overrideBusy, setOverrideBusy] = useState(false);
  const [distributionDate, setDistributionDate] = useState('');
  const [distributionGender, setDistributionGender] = useState('Semua');
  const [adminProducts, setAdminProducts] = useState([]);
  const [adminCategories, setAdminCategories] = useState([]);
  const [catalogBusy, setCatalogBusy] = useState(false);
  const [productForm, setProductForm] = useState({id:null,name:'',description:'',price:'',category_id:'',image_url:'',sku:'',is_available:true});
  const [categoryName, setCategoryName] = useState('');
  const [editingProduct, setEditingProduct] = useState(false);
  const [cashierAccounts, setCashierAccounts] = useState([]);
  const [cashierAccountsBusy, setCashierAccountsBusy] = useState(false);
  const [reportFrom, setReportFrom] = useState('');
  const [reportTo, setReportTo] = useState('');
  const [reportGender, setReportGender] = useState('Semua');
  const [cashierGenderFilter, setCashierGenderFilter] = useState('Semua');
  const isStaff = ['cashier','super_admin'].includes(profile?.role);
  const isAdmin = profile?.role === 'super_admin';

  useEffect(() => {
    if (!supabase) return;
    let alive = true;
    supabase.auth.getSession().then(({data}) => { if (alive) { setSession(data.session); setAuthLoading(false); } });
    const { data: listener } = supabase.auth.onAuthStateChange((_event, next) => { setSession(next); setProfile(null); });
    return () => { alive = false; listener.subscription.unsubscribe(); };
  }, []);

  useEffect(() => {
    let alive = true;
    (async () => {
      if (!supabase) { setDatabaseStatus('missing-config'); return; }
      const [{data: settings, error: settingsError}, {data: cats}, {data: prods, error: productError}, {data: scheduleRows}, {data: nextDate}] = await Promise.all([
        supabase.from('store_settings').select('*').eq('id', true).maybeSingle(),
        supabase.from('categories').select('id,name,sort_order').eq('is_active', true).order('sort_order'),
        supabase.from('products').select('id,name,description,price,image_url,category_id,categories(name)').eq('is_available', true).order('name'),
        supabase.from('delivery_weekdays').select('weekday,is_active').order('weekday'),
        supabase.rpc('next_delivery_date')
      ]);
      if (!alive) return;
      if (settings) setStoreSettings(s => ({...s, ...settings}));
      if (scheduleRows) setDeliveryWeekdays(scheduleRows);
      if (nextDate) setNextDeliveryDate(nextDate);
      if (cats?.length) setCategories(['Semua', ...cats.map(c => c.name)]);
      if (!productError && prods) setProducts(prods.map(p => ({id:p.id,name:p.name,description:p.description || '',price:Number(p.price),image:p.image_url,category:p.categories?.name || 'Lainnya',emoji:'🍽️'})));
      setDatabaseStatus(settingsError ? 'error' : 'connected');
      setMenuLoading(false);
    })();
    return () => { alive = false; };
  }, []);

  useEffect(() => {
    let alive = true;
    async function loadProfile() {
      if (!session?.user?.id || !supabase) { setProfile(null); return; }
      const {data,error} = await supabase.from('profiles').select('id,full_name,role,cashier_gender').eq('id',session.user.id).single();
      if (alive) setProfile(error ? null : data);
    }
    loadProfile(); return () => { alive = false; };
  }, [session?.user?.id]);

  async function loadAdminCatalog() {
    if (!supabase || !isAdmin) return;
    setCatalogBusy(true);
    const [{data: cats, error: catError}, {data: prods, error: prodError}] = await Promise.all([
      supabase.from('categories').select('id,name,sort_order,is_active').order('sort_order').order('name'),
      supabase.from('products').select('id,name,description,sku,price,image_url,category_id,is_available,categories(name)').order('name')
    ]);
    if (catError || prodError) setNotice(`Gagal memuat katalog admin: ${(catError || prodError).message}`);
    else { setAdminCategories(cats || []); setAdminProducts(prods || []); }
    setCatalogBusy(false);
  }
  useEffect(() => { if (isAdmin && page === 'catalog') loadAdminCatalog(); }, [isAdmin, page]);

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
    if (!supabase) return;
    const price = Number(productForm.price);
    if (!productForm.name.trim() || !Number.isSafeInteger(price) || price < 0) { setNotice('Nama produk wajib diisi dan harga harus berupa angka bulat minimal 0.'); return; }
    setCatalogBusy(true);
    const payload = {name:productForm.name.trim(),description:productForm.description.trim()||null,price,category_id:productForm.category_id?Number(productForm.category_id):null,image_url:productForm.image_url.trim()||null,sku:productForm.sku.trim()||null,is_available:productForm.is_available,updated_at:new Date().toISOString()};
    const query = productForm.id ? supabase.from('products').update(payload).eq('id',productForm.id) : supabase.from('products').insert(payload);
    const {error} = await query;
    setCatalogBusy(false);
    if (error) { setNotice(`Produk gagal disimpan: ${error.message}`); return; }
    setNotice(productForm.id?'Produk berhasil diperbarui.':'Produk berhasil ditambahkan.');
    resetProductForm(); await loadAdminCatalog(); await refreshCustomerCatalog();
  }
  async function refreshCustomerCatalog() {
    const [{data: cats}, {data: prods}] = await Promise.all([
      supabase.from('categories').select('id,name,sort_order').eq('is_active',true).order('sort_order'),
      supabase.from('products').select('id,name,description,price,image_url,category_id,categories(name)').eq('is_available',true).order('name')
    ]);
    if (cats) setCategories(['Semua',...cats.map(c=>c.name)]);
    if (prods) setProducts(prods.map(p=>({id:p.id,name:p.name,description:p.description||'',price:Number(p.price),image:p.image_url,category:p.categories?.name||'Lainnya',emoji:'🍽️'})));
  }
  async function addCategory(e) {
    e.preventDefault(); const name=categoryName.trim(); if(!name) return;
    const {error}=await supabase.from('categories').insert({name,sort_order:adminCategories.length,is_active:true});
    if(error) setNotice(`Kategori gagal ditambahkan: ${error.message}`); else {setCategoryName('');setNotice('Kategori berhasil ditambahkan.');await loadAdminCatalog();await refreshCustomerCatalog();}
  }
  async function toggleCategory(cat) {
    const {error}=await supabase.from('categories').update({is_active:!cat.is_active}).eq('id',cat.id);
    if(error) setNotice(`Kategori gagal diperbarui: ${error.message}`); else {setNotice(`Kategori ${cat.is_active?'dinonaktifkan':'diaktifkan'}.`);await loadAdminCatalog();await refreshCustomerCatalog();}
  }
  async function toggleProductAvailability(product) {
    const {error}=await supabase.from('products').update({is_available:!product.is_available,updated_at:new Date().toISOString()}).eq('id',product.id);
    if(error) setNotice(`Status produk gagal diperbarui: ${error.message}`); else {setNotice(`Produk ${product.is_available?'disembunyikan':'ditampilkan'} dari katalog pelanggan.`);await loadAdminCatalog();await refreshCustomerCatalog();}
  }

  async function loadOrders() {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return;
    setLoadingOrders(true);
    setOrders([]);
    if (profile.role === 'cashier' && !normalizeGender(profile.cashier_gender)) {
      setOrders([]);
      setNotice('Akun kasir belum diberi jalur Putra atau Putri. Minta Super Admin mengatur cashier_gender pada profil akun ini.');
      setLoadingOrders(false);
      return;
    }
    // Ambil dengan pagination agar antrean dan ekspor tidak diam-diam terpotong pada 300 baris.
    let allRows = [];
    let fetchError = null;
    for (let from = 0; from < 20000; from += 500) {
      let query = supabase.from('orders').select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)').order('created_at',{ascending:false}).range(from, from + 499);
      // Defense in depth: selain RLS di database, query kasir juga dibatasi pada jalurnya.
      if (profile.role === 'cashier') query = query.eq('guest_gender', normalizeGender(profile.cashier_gender));
      const {data,error} = await query;
      if (error) { fetchError = error; break; }
      allRows = allRows.concat(data || []);
      if (!data || data.length < 500) break;
    }
    if (fetchError) setNotice(`Gagal memuat pesanan: ${fetchError.message}`);
    else {
      setOrders(allRows.map(mapOrder));
      if (allRows.length >= 20000) setNotice('Data mencapai batas pemuatan 20.000 pesanan. Untuk laporan lebih lama, gunakan ekspor berdasarkan rentang tanggal pada pengembangan berikutnya.');
    }
    setLoadingOrders(false);
  }
  useEffect(() => { loadOrders(); }, [profile?.id, profile?.role, profile?.cashier_gender]);
  useEffect(() => {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return;
    const channel = supabase.channel('wdi-orders-live').on('postgres_changes',{event:'*',schema:'public',table:'orders'},()=>loadOrders()).subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [profile?.id, profile?.role, profile?.cashier_gender]);

  const cartCount = cart.reduce((s,x)=>s+x.qty,0);
  const cartTotal = cart.reduce((s,x)=>s+x.qty*x.price,0);
  const visibleMenu = useMemo(()=>category==='Semua'?products:products.filter(p=>p.category===category),[category,products]);
  function addToCart(item) { setCart(c=>{const found=c.find(x=>x.id===item.id);return found?c.map(x=>x.id===item.id?{...x,qty:x.qty+1}:x):[...c,{...item,qty:1}];}); setNotice(`${item.name} ditambahkan ke keranjang.`); }
  function changeQty(id,delta) { setCart(c=>c.map(x=>x.id===id?{...x,qty:x.qty+delta}:x).filter(x=>x.qty>0)); }

  async function placeOrder() {
    if (!supabase || databaseStatus !== 'connected') { setNotice('Database belum tersambung. Pesanan belum dikirim. Periksa konfigurasi Supabase.'); return; }
    if (!identity.name.trim() || !identity.dorm || !identity.className) { setNotice('Lengkapi nama, asrama, dan kelas.'); return; }
    if (!cart.length) { setNotice('Keranjang masih kosong.'); return; }
    const payload = cart.map(x=>({product_id:Number(x.id),quantity:x.qty}));
    // The database requires a 256-bit random guest access token (64 hex characters).
    if (!globalThis.crypto?.getRandomValues) { setNotice('Browser tidak mendukung pembuatan token pesanan yang aman. Gunakan browser terbaru melalui HTTPS.'); return; }
    const tokenBytes = new Uint8Array(32);
    globalThis.crypto.getRandomValues(tokenBytes);
    const accessToken = Array.from(tokenBytes, byte => byte.toString(16).padStart(2, '0')).join('');
    const {data,error} = await supabase.rpc('create_guest_order',{
      p_guest_name:identity.name.trim(),p_guest_gender:identity.gender,p_guest_dormitory:identity.dorm,p_guest_class:identity.className,
      p_guest_phone:identity.phone.trim() || null,p_customer_note:identity.note.trim() || null,p_items:payload,p_access_token:accessToken
    });
    if (error) { setNotice(`Pesanan gagal disimpan: ${error.message}. Pastikan migrasi Guest Checkout v2 sudah dijalankan.`); return; }
    const result = Array.isArray(data) ? data[0] : data;
    // Keep the bearer token on this device so a future guest-order lookup can use it.
    try {
      const tokenStoreKey = 'wdi_guest_order_tokens';
      const savedTokens = JSON.parse(localStorage.getItem(tokenStoreKey) || '[]');
      savedTokens.push({order_id:result.order_id,order_number:result.order_number,access_token:accessToken,created_at:new Date().toISOString()});
      localStorage.setItem(tokenStoreKey, JSON.stringify(savedTokens.slice(-50)));
    } catch (storageError) {
      console.warn('Token pesanan tidak dapat disimpan di perangkat ini.', storageError);
    }
    const items = cart.map(x=>({...x}));
    const message = ['*PESANAN WARUNG DARUL ILMI*',`Nomor: ${result.order_number}`,`Nama: ${identity.name}`,`Kategori: ${identity.gender}`,`Asrama: ${identity.dorm}`,`Kelas: ${identity.className}`,`Tanggal pengiriman: ${new Date(`${result.delivery_date}T00:00:00`).toLocaleDateString('id-ID',{weekday:'long',day:'numeric',month:'long',year:'numeric'})}`,'', '*Rincian pesanan:*',...items.map(x=>`- ${x.name} x${x.qty} = ${money(x.price*x.qty)}`),`*Total: ${money(result.total_amount)}*`,storeSettings.bank_name?`Bank: ${storeSettings.bank_name}`:'',storeSettings.bank_account_number?`Rekening: ${storeSettings.bank_account_number}`:'',storeSettings.bank_account_name?`Atas nama: ${storeSettings.bank_account_name}`:'',identity.note?`Catatan: ${identity.note}`:'',storeSettings.payment_instructions||'Mohon konfirmasi pembayaran. Barang diserahkan setelah pembayaran diverifikasi.','Silakan kirim bukti transfer berupa foto/screenshot langsung di chat WhatsApp ini. Bukti transfer tidak diunggah ke aplikasi.'].filter(Boolean).join('\n');
    setCart([]); setIdentity({name:'',gender:identity.gender,dorm:'',className:'',phone:'',note:''});
    setNotice(`Pesanan ${result.order_number} berhasil tersimpan. Tanggal pengiriman: ${result.delivery_date}.`);
    const selectedWhatsApp = identity.gender === 'Putri' ? (storeSettings.whatsapp_number_putri || storeSettings.whatsapp_number) : (storeSettings.whatsapp_number_putra || storeSettings.whatsapp_number);
    const wa=(selectedWhatsApp||'').replace(/\D/g,'');
    if (wa) window.open(`https://wa.me/${wa}?text=${encodeURIComponent(message)}`,'_blank','noopener,noreferrer');
    else setNotice(`Pesanan ${result.order_number} tersimpan online. Admin belum mengisi nomor WhatsApp pada Pengaturan.`);
  }

  async function updateOrder(id,patch) {
    if (!supabase) return;
    const target = orders.find(o => o.id === id);
    if (!target) { setNotice('Pesanan tidak ditemukan pada antrean yang sedang dibuka. Muat ulang data.'); return; }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin untuk mengubah pesanan dari jalur lain.'); return;
    }
    if (patch.status === 'delivered' && target.status !== 'ready') {
      setNotice('Pesanan hanya dapat ditandai diserahkan setelah berstatus Siap diserahkan.'); return;
    }
    const {error}=await supabase.from('orders').update(patch).eq('id',id);
    if (error) setNotice(`Perubahan gagal disimpan: ${error.message}`); else { setNotice('Perubahan pesanan tersimpan.'); await loadOrders(); }
  }
  async function saveSettings(e) {
    e.preventDefault(); setSettingsBusy(true);
    const {error}=await supabase.from('store_settings').update({store_name:storeSettings.store_name,whatsapp_number:storeSettings.whatsapp_number,whatsapp_number_putra:storeSettings.whatsapp_number_putra,whatsapp_number_putri:storeSettings.whatsapp_number_putri,bank_name:storeSettings.bank_name,bank_account_number:storeSettings.bank_account_number,bank_account_name:storeSettings.bank_account_name,payment_instructions:storeSettings.payment_instructions}).eq('id',true);
    setSettingsBusy(false); setNotice(error?`Gagal menyimpan: ${error.message}`:'Pengaturan rekening dan toko berhasil disimpan.');
  }
  async function loadDateOverrides() {
    if (!supabase || !isAdmin) return;
    const {data,error}=await supabase.from('delivery_date_overrides').select('delivery_date,is_delivery_day,note').gte('delivery_date',new Date().toISOString().slice(0,10)).order('delivery_date').limit(90);
    if(error) setNotice(`Gagal memuat pengecualian tanggal: ${error.message}`); else setDateOverrides(data||[]);
  }
  useEffect(()=>{ if(isAdmin && page==='settings') loadDateOverrides(); },[isAdmin,page]);
  async function saveDateOverride(e) {
    e.preventDefault(); if(!overrideDate) return; setOverrideBusy(true);
    const {error}=await supabase.from('delivery_date_overrides').upsert({delivery_date:overrideDate,is_delivery_day:overrideDelivery,note:overrideNote.trim()||null},{onConflict:'delivery_date'});
    if(error) setNotice(`Gagal menyimpan tanggal khusus: ${error.message}`); else { setNotice(overrideDelivery?'Tanggal khusus ditambahkan sebagai hari pengiriman.':'Tanggal ditandai tidak ada pengiriman.'); setOverrideDate('');setOverrideNote('');await loadDateOverrides();const n=await supabase.rpc('next_delivery_date');if(!n.error)setNextDeliveryDate(n.data); }
    setOverrideBusy(false);
  }
  async function deleteDateOverride(date) {
    const {error}=await supabase.from('delivery_date_overrides').delete().eq('delivery_date',date);
    if(error) setNotice(`Gagal menghapus pengecualian: ${error.message}`); else {setNotice('Pengecualian tanggal dihapus.');await loadDateOverrides();const n=await supabase.rpc('next_delivery_date');if(!n.error)setNextDeliveryDate(n.data);}
  }
  async function saveDeliverySchedule() {
    setScheduleBusy(true);
    const rows = Array.from({length:7},(_,weekday)=>({weekday,is_active:deliveryWeekdays.find(x=>x.weekday===weekday)?.is_active || false}));
    const {error}=await supabase.from('delivery_weekdays').upsert(rows,{onConflict:'weekday'});
    const dateResult=await supabase.rpc('next_delivery_date');
    if(!dateResult.error)setNextDeliveryDate(dateResult.data);
    setScheduleBusy(false);
    setNotice(error?`Gagal menyimpan jadwal: ${error.message}`:'Jadwal mingguan berhasil disimpan.');
  }
  const cashierGender = normalizeGender(profile?.cashier_gender);
  const scopedOrders = profile?.role === 'cashier' ? orders.filter(o => o.customer.gender === cashierGender) : orders;
  const effectiveCashierGenderFilter = profile?.role === 'cashier' ? cashierGender : cashierGenderFilter;
  const filteredOrders = scopedOrders.filter(o => (filter==='Semua'||o.status===statusValues[filter]) && (effectiveCashierGenderFilter==='Semua'||o.customer.gender===effectiveCashierGenderFilter) && `${o.number} ${o.customer.name} ${o.customer.dorm} ${o.customer.className}`.toLowerCase().includes(search.trim().toLowerCase()));
  const availableDeliveryDates = [...new Set(scopedOrders.map(o=>o.deliveryDate).filter(Boolean))].sort();
  const suggestedDistributionDate = availableDeliveryDates.find(d=>d >= new Date().toISOString().slice(0,10)) || availableDeliveryDates.at(-1) || nextDeliveryDate || new Date().toISOString().slice(0,10);
  const effectiveDistributionDate = distributionDate || suggestedDistributionDate;
  const effectiveDistributionGender = profile?.role === 'cashier' ? cashierGender : distributionGender;
  const distributionOrders = scopedOrders.filter(o => o.deliveryDate === effectiveDistributionDate && o.status !== 'cancelled' && (!effectiveDistributionGender || effectiveDistributionGender === 'Semua' || o.customer.gender === effectiveDistributionGender));
  const distributionGroups = Object.values(distributionOrders.reduce((acc, order) => { const key = `${order.customer.gender} · ${order.customer.dorm || 'Tanpa asrama'}`; (acc[key] ||= []).push(order); return acc; }, {})).sort((a,b) => `${a[0].customer.gender}-${a[0].customer.dorm}`.localeCompare(`${b[0].customer.gender}-${b[0].customer.dorm}`,'id'));
  const invalidReportRange = Boolean(reportFrom && reportTo && reportFrom > reportTo);
  // Rentang laporan menggunakan tanggal pengiriman, dan daftar ini dipakai bersama
  // oleh pratinjau maupun ekspor agar hasil Excel selalu mengikuti filter di layar.
  const reportOrders = invalidReportRange ? [] : orders.filter(o => (!reportFrom || o.deliveryDate >= reportFrom) && (!reportTo || o.deliveryDate <= reportTo) && (reportGender === 'Semua' || o.customer.gender === reportGender));
  async function loadCashierAccounts() {
    if (!supabase || !isAdmin) return;
    setCashierAccountsBusy(true);
    const {data,error} = await supabase.from('profiles').select('id,full_name,role,cashier_gender').eq('role','cashier').order('full_name');
    if (error) setNotice(`Gagal memuat akun kasir: ${error.message}`);
    else setCashierAccounts(data || []);
    setCashierAccountsBusy(false);
  }
  async function saveCashierGender(accountId, gender) {
    const {error} = await supabase.from('profiles').update({cashier_gender:gender}).eq('id',accountId).eq('role','cashier');
    if (error) setNotice(`Jalur kasir gagal disimpan: ${error.message}`);
    else { setNotice(`Jalur akun berhasil diatur ke ${gender}.`); await loadCashierAccounts(); }
  }
  useEffect(()=>{ if(isAdmin && page==='settings') loadCashierAccounts(); },[isAdmin,page]);
  async function exportWorkbook() {
    if (!isAdmin) { setNotice('Ekspor laporan hanya tersedia untuk Super Admin.'); return; }
    if (invalidReportRange) { setNotice('Rentang tanggal tidak valid. Tanggal mulai harus sama dengan atau sebelum tanggal akhir.'); return; }
    if (!reportOrders.length) { setNotice('Tidak ada pesanan pada rentang tanggal pengiriman yang dipilih.'); return; }
    try {
      // Ambil seluruh nama produk katalog, bukan hanya produk yang laku pada periode ini.
      // Dengan demikian produk yang tidak dipesan tetap memiliki kolom dan bernilai 0.
      const { data: catalogProducts, error: catalogError } = await supabase
        .from('products').select('name').order('name');
      if (catalogError) throw catalogError;

      // Sheet Pesanan: satu baris per nomor transaksi. Nama santri, kelas, dan asrama
      // selalu menjadi tiga kolom pertama. Pesanan berbeda tetap menjadi baris terpisah.
      const productNameMap = new Map();
      for (const product of (catalogProducts || [])) {
        const name = String(product.name || '').trim();
        if (name) productNameMap.set(name.toLocaleLowerCase('id'), name);
      }
      // Produk pada transaksi lama tetap disertakan walaupun sudah tidak ada di katalog.
      for (const order of reportOrders) {
        for (const item of order.items) {
          const name = String(item.name || '').trim();
          if (name && !productNameMap.has(name.toLocaleLowerCase('id'))) {
            productNameMap.set(name.toLocaleLowerCase('id'), name);
          }
        }
      }
      const productNames = [...productNameMap.values()].sort((a, b) => a.localeCompare(b, 'id'));
      const productKey = name => String(name || '').trim().toLocaleLowerCase('id');
      const matrixHeaders = ['Nama Santri', 'Kelas', 'Asrama', 'Kategori', 'Tanggal Pengiriman', 'Nomor Pesanan', ...productNames, 'Total Pesanan', 'Status Pesanan'];
      const matrixRows = [matrixHeaders];
      for (const order of reportOrders) {
        const quantities = new Map();
        for (const item of order.items) {
          const key = productKey(item.name);
          if (key) quantities.set(key, (quantities.get(key) || 0) + Number(item.qty || 0));
        }
        matrixRows.push([
          order.customer.name || '', order.customer.className || '', order.customer.dorm || '',
          order.customer.gender || '', order.deliveryDate || '', order.number || '',
          ...productNames.map(name => quantities.get(productKey(name)) || 0),
          Number(order.total || 0), statusLabels[order.status] || order.status || ''
        ]);
      }
      // Dua sheet berikut tetap memakai data transaksi yang sama dengan filter tanggal.
      const itemRows = reportOrders.flatMap(o => o.items.map(i => ({ 'Nomor Pesanan':o.number, 'Tanggal Kirim':o.deliveryDate, 'Nama Santri':o.customer.name, 'Kategori':o.customer.gender, 'Asrama':o.customer.dorm, 'Kelas':o.customer.className, 'Produk':i.name, 'Jumlah':i.qty, 'Harga Satuan':i.price, 'Subtotal':i.price*i.qty })));
      const summaryRows = ['Putra','Putri'].map(gender => { const rows=reportOrders.filter(o=>o.customer.gender===gender); return {'Kategori':gender,'Jumlah Pesanan':rows.length,'Jumlah Item':rows.reduce((n,o)=>n+o.items.reduce((m,i)=>m+i.qty,0),0),'Nilai Pesanan':rows.reduce((n,o)=>n+o.total,0),'Sudah Diserahkan':rows.filter(o=>o.status==='delivered').length,'Belum Selesai':rows.filter(o=>!['delivered','cancelled'].includes(o.status)).length}; });
      const wb = XLSX.utils.book_new();
      const orderSheet = XLSX.utils.aoa_to_sheet(matrixRows);
      orderSheet['!cols'] = matrixHeaders.map((header, index) => ({ wch: index === 0 ? 26 : index < 3 ? 18 : header.length > 22 ? 22 : Math.max(14, header.length + 2) }));
      orderSheet['!autofilter'] = { ref: XLSX.utils.encode_range({s:{r:0,c:0}, e:{r:matrixRows.length-1,c:matrixHeaders.length-1}}) };
      XLSX.utils.book_append_sheet(wb, orderSheet, 'Pesanan');
      XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(itemRows.length ? itemRows : [{'Informasi':'Belum ada rincian item'}]), 'Rincian Item');
      XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(summaryRows), 'Ringkasan');
      const fileName = `laporan-warung-darul-ilmi-${reportFrom || 'awal'}-${reportTo || 'terkini'}.xlsx`;
      XLSX.writeFile(wb, fileName, { compression: true });
      setNotice(`Laporan berhasil dibuat: ${reportOrders.length} transaksi. Kolom produk: ${productNames.length}. File: ${fileName}.`);
    } catch (error) { setNotice(`Ekspor Excel gagal: ${error?.message || error}`); }
  }
  function printKitchenTickets(list = distributionOrders) {
    if (!list.length) { setNotice('Tidak ada pesanan pada tanggal dan filter tersebut.'); return; }
    const html = list.map(o => `<article class="ticket"><header><b>WARUNG DARUL ILMI</b><strong>${escapeHtml(o.number)}</strong></header><h2>${escapeHtml(o.customer.name)}</h2><p>${escapeHtml(o.customer.gender)} · ${escapeHtml(o.customer.dorm)} · ${escapeHtml(o.customer.className)}</p><p><b>Tanggal distribusi:</b> ${escapeHtml(o.deliveryDate)}</p><hr>${o.items.map(i=>`<div class="item"><span>${escapeHtml(i.name)}</span><b>× ${Number(i.qty)}</b></div>`).join('')}<hr><p><b>Catatan:</b> ${escapeHtml(o.note || '—')}</p><footer>Periksa jumlah dan identitas sebelum diserahkan.</footer></article>`).join('');
    const printDocument = `<!doctype html><html><head><meta charset="utf-8"><title>Tiket Dapur</title><style>body{font:14px Arial,sans-serif;color:#111}.ticket{border:1px dashed #555;padding:18px;margin:0 auto 18px;max-width:420px;page-break-inside:avoid}.ticket header,.item{display:flex;justify-content:space-between;gap:15px}.ticket h2{margin:14px 0 4px}.ticket p{margin:6px 0}.ticket footer{margin-top:16px;font-size:11px}@media print{.ticket{page-break-after:always;margin:0 auto;border:1px dashed #555}}</style></head><body>${html}</body></html>`;
    const frame = document.createElement('iframe');
    frame.setAttribute('aria-hidden', 'true');
    frame.style.position = 'fixed'; frame.style.width = '1px'; frame.style.height = '1px'; frame.style.opacity = '0'; frame.style.border = '0';
    frame.onload = () => {
      try { frame.contentWindow.focus(); frame.contentWindow.print(); }
      catch { setNotice('Browser tidak mengizinkan proses cetak. Coba gunakan Chrome atau Edge terbaru.'); }
      frame.contentWindow.addEventListener('afterprint', () => frame.remove(), { once: true });
    };
    frame.srcdoc = printDocument;
    document.body.appendChild(frame);
  }

  if (staffLoginOpen) return <AuthScreen onClose={()=>setStaffLoginOpen(false)} />;
  return <div className="app-shell">
    <header className="topbar"><button className="brand" onClick={()=>setPage('order')} aria-label="Ke halaman pemesanan"><span className="brand-mark">و</span><span><strong>Warung Darul Ilmi</strong><small>Pesan mudah, berkah insyaallah</small></span></button>
      <nav className="nav"><button className={page==='order'?'active':''} onClick={()=>setPage('order')}>Pemesanan</button>{isStaff&&<><button className={page==='cashier'?'active':''} onClick={()=>setPage('cashier')}>Kasir</button><button className={page==='distribution'?'active':''} onClick={()=>setPage('distribution')}>Distribusi & Dapur</button></>}{isAdmin&&<><button className={page==='admin'?'active':''} onClick={()=>setPage('admin')}>Super Admin</button><button className={page==='reports'?'active':''} onClick={()=>setPage('reports')}>Laporan</button><button className={page==='catalog'?'active':''} onClick={()=>setPage('catalog')}>Kelola Katalog</button><button className={page==='settings'?'active':''} onClick={()=>setPage('settings')}>Pengaturan</button></>}{session&&profile&&<span className="account-chip">{profile.full_name||session.user.email} · {profile.role}</span>}{session?<button onClick={async()=>{await supabase.auth.signOut();setProfile(null);setPage('order');}}>Keluar</button>:<button onClick={()=>setStaffLoginOpen(true)}>Login Staf</button>}</nav>
    </header>
    <main className="main">
      <div className={`notice db-status db-${databaseStatus}`} role="status">{databaseStatus==='checking'?'Memeriksa koneksi Supabase…':databaseStatus==='connected'?'Terhubung ke Supabase · Katalog dan checkout menggunakan database online.':databaseStatus==='missing-config'?'Supabase belum dikonfigurasi. Isi .env.local terlebih dahulu.':'Koneksi database bermasalah. Periksa URL, publishable key, dan tabel.'}</div>
      {session&&authLoading&&<div className="notice">Memuat akses petugas…</div>}{session&&!authLoading&&!profile&&<div className="notice">Profil petugas tidak ditemukan atau belum memiliki akses.</div>}{notice&&<div className="notice" role="status"><span>{notice}</span><button onClick={()=>setNotice('')} aria-label="Tutup pemberitahuan">×</button></div>}
      {page==='order'&&<section>
        <div className="hero"><div className="hero-pattern">✦</div><p className="eyebrow">SELAMAT DATANG</p><h1>Pesan kebutuhanmu<br/><em>dengan mudah.</em></h1><p className="hero-copy">Pilih menu, periksa pesanan, lalu konfirmasi melalui WhatsApp.</p><div className="hero-meta"><span>✧ Praktis</span><span>✧ Tertata</span><span>✧ Mudah dikonfirmasi</span></div></div>
        <div className="section-heading"><div><p className="eyebrow">LANGKAH 01</p><h2>Identitas santri</h2><p className="muted">Data ini membantu petugas mengantarkan pesanan ke tempat yang tepat.</p></div></div>
        <div className="panel identity-grid"><label>Nama santri<input value={identity.name} onChange={e=>setIdentity({...identity,name:e.target.value})} placeholder="Masukkan nama lengkap" required/></label><label>Kategori<select value={identity.gender} onChange={e=>setIdentity({...identity,gender:e.target.value,dorm:''})}><option>Putra</option><option>Putri</option></select></label><label>Asrama<input value={identity.dorm} onChange={e=>setIdentity({...identity,dorm:e.target.value})} placeholder="Nama asrama" required/></label><label>Kelas<input value={identity.className} onChange={e=>setIdentity({...identity,className:e.target.value})} placeholder="Contoh: 8 MTs" required/></label><label>Nomor WhatsApp (opsional)<input inputMode="tel" value={identity.phone} onChange={e=>setIdentity({...identity,phone:e.target.value})} placeholder="08xxxxxxxxxx"/></label><div className="wide delivery-auto"><strong>Jadwal pengiriman otomatis</strong><span>{nextDeliveryDate ? `Perkiraan pengiriman berikutnya: ${new Date(`${nextDeliveryDate}T00:00:00`).toLocaleDateString('id-ID',{weekday:'long',day:'numeric',month:'long',year:'numeric'})}` : 'Tanggal ditentukan otomatis oleh jadwal admin.'}</span></div></div>
        {(storeSettings.bank_name||storeSettings.bank_account_number||storeSettings.payment_instructions)&&<div className="panel payment-info"><strong>Informasi pembayaran</strong><p>{storeSettings.bank_name||'Bank'} · {storeSettings.bank_account_number||'Nomor rekening belum diatur'}</p><p>Atas nama: {storeSettings.bank_account_name||'Belum diatur'}</p>{storeSettings.payment_instructions&&<small>{storeSettings.payment_instructions}</small>}</div>}
        <div className="section-heading menu-heading"><div><p className="eyebrow">LANGKAH 02</p><h2>Pilih menu</h2><p className="muted">Produk dan harga dibaca dari katalog Supabase.</p></div><span className="cart-pill">🛒 {cartCount} item</span></div>
        <div className="chips">{categories.map(c=><button key={c} className={category===c?'selected':''} onClick={()=>setCategory(c)}>{c}</button>)}</div>
        {menuLoading&&<div className="panel">Memuat katalog…</div>}
        <div className="menu-grid">{visibleMenu.map(item=><article className="menu-card" key={item.id}><div className="food-art">{item.image?<img src={item.image} alt={item.name}/>:item.emoji}</div><div className="menu-info"><span className="category-label">{item.category}</span><h3>{item.name}</h3><p>{item.description}</p><div className="menu-bottom"><strong>{money(item.price)}</strong><button onClick={()=>addToCart(item)}>+ Tambah</button></div></div></article>)}</div>
        <div className="section-heading"><div><p className="eyebrow">LANGKAH 03</p><h2>Keranjang pesanan</h2></div></div>
        <div className="panel cart-panel">{cart.length===0?<p className="empty">Keranjang masih kosong. Tambahkan menu pilihanmu.</p>:<>{cart.map(item=><div className="cart-row" key={item.id}><div><strong>{item.name}</strong><small>{money(item.price)} / item</small></div><div className="qty"><button onClick={()=>changeQty(item.id,-1)} aria-label={`Kurangi ${item.name}`}>−</button><b>{item.qty}</b><button onClick={()=>changeQty(item.id,1)} aria-label={`Tambah ${item.name}`}>+</button></div><strong>{money(item.price*item.qty)}</strong></div>)}<label>Catatan untuk dapur/kasir<textarea value={identity.note} onChange={e=>setIdentity({...identity,note:e.target.value})} placeholder="Contoh: sambal dipisah, tanpa sendok plastik"/></label><div className="cart-total"><span>Total pesanan</span><strong>{money(cartTotal)}</strong></div><button className="primary full" onClick={placeOrder}>Simpan pesanan & lanjut WhatsApp <span>→</span></button><p className="fine-print">Pesanan disimpan ke Supabase terlebih dahulu. Pembayaran diverifikasi petugas sebelum barang diserahkan.</p></>}</div>
      </section>}
      {page==='cashier'&&isStaff&&<section><div className="page-intro"><p className="eyebrow">AREA OPERASIONAL</p><h1>Antrean Kasir {profile?.role==='cashier'?profile.cashier_gender:'Putra & Putri'}</h1><p className="muted">{profile?.role==='cashier'?`Akses dibatasi untuk pesanan santri ${profile.cashier_gender}.`:'Super Admin dapat memantau seluruh pesanan.'} Pemeriksaan pembayaran dan bukti transfer dilakukan melalui WhatsApp, bukan di aplikasi.</p>{profile?.role==='cashier'&&!['Putra','Putri'].includes(profile.cashier_gender)&&<div className="notice">Akun kasir belum memiliki jalur Putra/Putri. Super Admin harus mengatur kolom cashier_gender pada profil akun.</div>}</div><div className="stats"><div className="stat-card"><small>Menunggu konfirmasi</small><strong>{scopedOrders.filter(o=>o.status==='pending').length}</strong></div><div className="stat-card"><small>Sedang diproses</small><strong>{scopedOrders.filter(o=>['confirmed','preparing'].includes(o.status)).length}</strong></div><div className="stat-card"><small>Siap diserahkan</small><strong>{scopedOrders.filter(o=>o.status==='ready').length}</strong></div></div><div className="toolbar"><h2>Antrean pesanan</h2><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Cari nama, tiket, asrama…"/><label className="cashier-gender-filter">Jalur pesanan<select aria-label="Filter jalur kasir" value={profile?.role==='cashier'?cashierGender:cashierGenderFilter} onChange={e=>setCashierGenderFilter(e.target.value)} disabled={profile?.role==='cashier'}><option value="Semua">Semua jalur (Putra & Putri)</option><option value="Putra">Khusus Putra</option><option value="Putri">Khusus Putri</option></select>{profile?.role==='cashier'&&<small>Filter dikunci sesuai penugasan akun kasir.</small>}</label><select aria-label="Filter status pesanan" value={filter} onChange={e=>setFilter(e.target.value)}><option>Semua</option><option>Menunggu</option><option>Dikonfirmasi</option><option>Diproses</option><option>Siap diserahkan</option><option>Sudah diserahkan</option><option>Dibatalkan</option></select><button onClick={loadOrders}>Muat ulang</button></div>{loadingOrders&&<p className="muted">Memuat pesanan…</p>}<OrderList orders={filteredOrders} onStatus={(id,v)=>updateOrder(id,{status:v})}/></section>}
      {page==='distribution'&&isStaff&&<section><div className="page-intro"><p className="eyebrow">DAPUR & PENYERAHAN</p><h1>Distribusi pesanan</h1><p className="muted">Kelompokkan pesanan berdasarkan tanggal pengiriman, kategori santri, dan asrama. Tanggal otomatis memilih tanggal pengiriman yang memiliki pesanan. Hanya pesanan berstatus siap diserahkan yang dapat ditandai sudah diserahkan.</p></div><div className="panel distribution-tools"><label>Tanggal pengiriman<input type="date" value={effectiveDistributionDate} onChange={e=>setDistributionDate(e.target.value)}/></label><label>Kategori santri<select value={effectiveDistributionGender} onChange={e=>setDistributionGender(e.target.value)} disabled={profile?.role==='cashier'}>{profile?.role==='super_admin'&&<option>Semua</option>}<option>Putra</option><option>Putri</option></select></label><div className="distribution-actions"><button className="primary" onClick={()=>printKitchenTickets()}>Cetak semua tiket dapur</button><button onClick={loadOrders}>Muat ulang pesanan</button></div></div><div className="stats"><div className="stat-card"><small>Jumlah pesanan</small><strong>{distributionOrders.length}</strong></div><div className="stat-card"><small>Total item</small><strong>{distributionOrders.reduce((n,o)=>n+o.items.reduce((m,i)=>m+i.qty,0),0)}</strong></div><div className="stat-card"><small>Nilai pesanan</small><strong>{money(distributionOrders.reduce((n,o)=>n+o.total,0))}</strong></div></div>{!distributionOrders.length?<div className="panel empty">Belum ada pesanan pada {effectiveDistributionDate}. Pilih tanggal lain atau muat ulang pesanan.</div>:distributionGroups.map(group=><div className="distribution-group" key={`${group[0].customer.gender}-${group[0].customer.dorm}`}><div className="section-heading"><div><p className="eyebrow">KELOMPOK DISTRIBUSI</p><h2>{group[0].customer.gender} · {group[0].customer.dorm}</h2></div><span className="cart-pill">{group.length} pesanan</span></div>{group.map(o=><article className="panel distribution-card" key={o.id}><div><span className="category-label">{o.number}</span><h3>{o.customer.name}</h3><p className="muted">{o.customer.className} · {o.items.reduce((n,i)=>n+i.qty,0)} item · {money(o.total)}</p><div className="order-items">{o.items.map((i,k)=><div key={k}><span>{i.name}</span><b>× {i.qty}</b></div>)}</div>{o.note&&<p className="fine-print">Catatan dapur: {o.note}</p>}</div><div className="distribution-card-actions"><span className="status">{statusLabels[o.status]||o.status}</span><button onClick={()=>printKitchenTickets([o])}>Cetak tiket</button><button className="primary" onClick={()=>updateOrder(o.id,{status:'delivered'})} disabled={o.status!=='ready'}>Tandai diserahkan</button></div></article>)}</div>)}</section>}
      {page==='admin'&&isAdmin&&<section><div className="page-intro"><p className="eyebrow">PUSAT KENDALI</p><h1>Portal Super Admin</h1><p className="muted">Pemantauan gabungan antrean Putra dan Putri.</p></div><div className="stats"><div className="stat-card"><small>Jumlah transaksi</small><strong>{orders.length}</strong></div><div className="stat-card"><small>Nilai seluruh pesanan</small><strong>{money(orders.reduce((s,o)=>s+o.total,0))}</strong></div><div className="stat-card"><small>Pesanan belum selesai</small><strong>{orders.filter(o=>!['delivered','cancelled'].includes(o.status)).length}</strong></div></div><div className="split-stats"><div className="panel"><span className="category-label">SANTRI PUTRA</span><h2>{orders.filter(o=>o.customer.gender==='Putra').length}</h2><p className="muted">Pesanan masuk</p></div><div className="panel"><span className="category-label">SANTRI PUTRI</span><h2>{orders.filter(o=>o.customer.gender==='Putri').length}</h2><p className="muted">Pesanan masuk</p></div></div><div className="panel settings-panel"><h2>Laporan dan ekspor Excel</h2><p className="muted">Pilih rentang tanggal pengiriman, lihat transaksi yang masuk dalam periode tersebut, lalu unduh laporan Excel dengan satu baris untuk setiap transaksi santri.</p><button className="primary" type="button" onClick={()=>setPage('reports')}>Buka Laporan →</button></div></section>}
      {page==='reports'&&isAdmin&&<section><div className="page-intro"><p className="eyebrow">LAPORAN OPERASIONAL</p><h1>Laporan pesanan</h1><p className="muted">Filter berdasarkan tanggal pengiriman dan kategori santri. Pratinjau serta seluruh lembar Excel mengikuti filter yang dipilih.</p></div><div className="stats"><div className="stat-card"><small>Transaksi dalam laporan</small><strong>{reportOrders.length}</strong></div><div className="stat-card"><small>Total nilai pesanan</small><strong>{money(reportOrders.reduce((sum,o)=>sum+o.total,0))}</strong></div><div className="stat-card"><small>Jumlah item</small><strong>{reportOrders.reduce((sum,o)=>sum+o.items.reduce((n,i)=>n+Number(i.qty||0),0),0)}</strong></div></div><div className="panel" style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:14,alignItems:'end'}}><label>Dari tanggal pengiriman<input type="date" value={reportFrom} onChange={e=>setReportFrom(e.target.value)}/></label><label>Sampai tanggal pengiriman<input type="date" value={reportTo} min={reportFrom||undefined} onChange={e=>setReportTo(e.target.value)}/></label><label>Kategori santri<select value={reportGender} onChange={e=>setReportGender(e.target.value)}><option value="Semua">Semua (Putra & Putri)</option><option value="Putra">Khusus Putra</option><option value="Putri">Khusus Putri</option></select></label><div style={{display:'flex',gap:8,flexWrap:'wrap'}}><button type="button" onClick={()=>{setReportFrom('');setReportTo('');setReportGender('Semua');}}>Reset filter</button><button type="button" onClick={loadOrders}>Muat ulang</button><button className="primary" type="button" onClick={exportWorkbook}>Unduh Excel (.xlsx)</button></div></div><div className="toolbar"><h2>Daftar transaksi ({reportOrders.length})</h2><span className="muted">{reportFrom||'Awal'} s.d. {reportTo||'Terbaru'} · {reportGender==='Semua'?'Putra & Putri':reportGender}</span></div>{invalidReportRange?<div className="panel empty">Tanggal mulai tidak boleh melewati tanggal akhir.</div>:<OrderList orders={reportOrders} onStatus={(id,v)=>updateOrder(id,{status:v})}/>}</section>}
      {page==='catalog'&&isAdmin&&<section>
        <div className="page-intro"><p className="eyebrow">MANAJEMEN MENU</p><h1>Kelola katalog</h1><p className="muted">Tambah dan ubah produk, harga, kategori, serta ketersediaan yang tampil di halaman pelanggan.</p></div>
        <form className="panel settings-panel catalog-form" onSubmit={saveProduct}>
          <div className="section-heading"><div><h2>{editingProduct?'Ubah produk':'Tambah produk baru'}</h2><p className="muted">Harga dimasukkan dalam rupiah tanpa titik atau simbol.</p></div>{editingProduct&&<button type="button" onClick={resetProductForm}>Batal edit</button>}</div>
          <div className="catalog-form-grid">
            <label>Nama produk<input value={productForm.name} onChange={e=>setProductForm({...productForm,name:e.target.value})} placeholder="Contoh: Nasi Ayam" required/></label>
            <label>Harga (Rp)<input type="number" min="0" step="1" value={productForm.price} onChange={e=>setProductForm({...productForm,price:e.target.value})} placeholder="12000" required/></label>
            <label>Kategori<select value={productForm.category_id} onChange={e=>setProductForm({...productForm,category_id:e.target.value})}><option value="">Tanpa kategori</option>{adminCategories.filter(c=>c.is_active).map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
            <label>SKU / kode produk (opsional)<input value={productForm.sku} onChange={e=>setProductForm({...productForm,sku:e.target.value})} placeholder="MISAL: MN-001"/></label>
            <label className="catalog-wide">Deskripsi<textarea value={productForm.description} onChange={e=>setProductForm({...productForm,description:e.target.value})} placeholder="Keterangan singkat produk"/></label>
            <label className="catalog-wide">URL gambar (opsional)<input type="url" value={productForm.image_url} onChange={e=>setProductForm({...productForm,image_url:e.target.value})} placeholder="https://..."/></label>
          </div>
          <label className="inline-check"><input type="checkbox" checked={productForm.is_available} onChange={e=>setProductForm({...productForm,is_available:e.target.checked})}/> Tampilkan produk di katalog pelanggan</label>
          <button className="primary" disabled={catalogBusy}>{catalogBusy?'Menyimpan…':editingProduct?'Simpan perubahan':'Tambah produk'}</button>
        </form>
        <div className="panel settings-panel"><h2>Kategori produk</h2><form className="category-add" onSubmit={addCategory}><input value={categoryName} onChange={e=>setCategoryName(e.target.value)} placeholder="Nama kategori baru" required/><button className="primary" disabled={catalogBusy}>Tambah kategori</button></form><div className="category-admin-list">{adminCategories.map(cat=><div className="category-admin-row" key={cat.id}><div><strong>{cat.name}</strong><small>{cat.is_active?'Aktif':'Nonaktif'}</small></div><button type="button" onClick={()=>toggleCategory(cat)}>{cat.is_active?'Nonaktifkan':'Aktifkan'}</button></div>)}</div></div>
        <div className="toolbar"><h2>Daftar produk ({adminProducts.length})</h2><button onClick={loadAdminCatalog}>Muat ulang</button></div>
        {catalogBusy&&<p className="muted">Memuat katalog…</p>}
        <div className="admin-product-list">{adminProducts.map(product=><article className="panel admin-product-row" key={product.id}><div className="admin-product-image">{product.image_url?<img src={product.image_url} alt=""/>:'🍽️'}</div><div className="admin-product-detail"><span className="category-label">{product.categories?.name||'Tanpa kategori'} · {product.is_available?'Tampil':'Disembunyikan'}</span><h3>{product.name}</h3><p>{product.description||'Tidak ada deskripsi.'}</p><strong>{money(product.price)}</strong></div><div className="admin-product-actions"><button onClick={()=>editProduct(product)}>Edit</button><button onClick={()=>toggleProductAvailability(product)}>{product.is_available?'Sembunyikan':'Tampilkan'}</button></div></article>)}</div>
      </section>}
      {page==='settings'&&isAdmin&&<section><div className="page-intro"><p className="eyebrow">KONFIGURASI</p><h1>Pengaturan pusat</h1><p className="muted">Kelola identitas toko, rekening transfer, dan hari pengiriman.</p></div><form className="panel settings-panel" onSubmit={saveSettings}><h2>Informasi toko & pembayaran</h2><label>Nama warung<input value={storeSettings.store_name||''} onChange={e=>setStoreSettings({...storeSettings,store_name:e.target.value})}/></label><label>WhatsApp Kasir Putra<input inputMode="numeric" value={storeSettings.whatsapp_number_putra||''} onChange={e=>setStoreSettings({...storeSettings,whatsapp_number_putra:e.target.value})} placeholder="628xxxxxxxxxx"/></label><label>WhatsApp Kasir Putri<input inputMode="numeric" value={storeSettings.whatsapp_number_putri||''} onChange={e=>setStoreSettings({...storeSettings,whatsapp_number_putri:e.target.value})} placeholder="628xxxxxxxxxx"/></label><label>WhatsApp Admin Umum (cadangan)<input inputMode="numeric" value={storeSettings.whatsapp_number||''} onChange={e=>setStoreSettings({...storeSettings,whatsapp_number:e.target.value})} placeholder="628xxxxxxxxxx"/></label><label>Nama bank<input value={storeSettings.bank_name||''} onChange={e=>setStoreSettings({...storeSettings,bank_name:e.target.value})} placeholder="Nama bank"/></label><label>Nomor rekening<input inputMode="numeric" value={storeSettings.bank_account_number||''} onChange={e=>setStoreSettings({...storeSettings,bank_account_number:e.target.value})} placeholder="Nomor rekening"/></label><label>Atas nama<input value={storeSettings.bank_account_name||''} onChange={e=>setStoreSettings({...storeSettings,bank_account_name:e.target.value})} placeholder="Nama pemilik rekening"/></label><label>Instruksi pembayaran<textarea value={storeSettings.payment_instructions||''} onChange={e=>setStoreSettings({...storeSettings,payment_instructions:e.target.value})} placeholder="Cantumkan nominal dan nomor pesanan pada berita transfer."/></label><p className="fine-print">Nomor WhatsApp menggunakan kode negara 62 tanpa tanda + atau spasi. Pesanan Putra diarahkan ke Kasir Putra, sedangkan pesanan Putri ke Kasir Putri. Nomor Admin Umum dipakai sebagai cadangan jika nomor kasir terkait belum diisi.</p><button className="primary" disabled={settingsBusy}>{settingsBusy?'Menyimpan…':'Simpan pengaturan toko'}</button></form><div className="panel settings-panel"><h2>Jadwal pengiriman mingguan</h2><p className="muted">Pelanggan akan mendapat tanggal pengiriman aktif terdekat secara otomatis.</p><div className="chips">{['Minggu','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu'].map((day,weekday)=>{const active=deliveryWeekdays.find(x=>x.weekday===weekday)?.is_active||false;return <button type="button" key={day} className={active?'selected':''} onClick={()=>setDeliveryWeekdays(old=>[...old.filter(x=>x.weekday!==weekday),{weekday,is_active:!active}])}>{day} {active?'✓':'+'}</button>;})}</div><p className="fine-print">Tanggal pengiriman berikutnya: {nextDeliveryDate||'Belum tersedia — aktifkan minimal satu hari.'}</p><button className="primary" type="button" onClick={saveDeliverySchedule} disabled={scheduleBusy}>{scheduleBusy?'Menyimpan…':'Simpan jadwal mingguan'}</button></div><div className="panel settings-panel"><h2>Pengecualian tanggal pengiriman</h2><p className="muted">Tambahkan tanggal libur (tidak ada pengiriman) atau tanggal pengiriman khusus. Aturan tanggal khusus mengesampingkan jadwal mingguan.</p><form className="category-add" onSubmit={saveDateOverride}><label>Tanggal<input type="date" value={overrideDate} min={new Date().toISOString().slice(0,10)} onChange={e=>setOverrideDate(e.target.value)} required/></label><label>Jenis tanggal<select value={overrideDelivery?'delivery':'closed'} onChange={e=>setOverrideDelivery(e.target.value==='delivery')}><option value="closed">Libur / tidak ada pengiriman</option><option value="delivery">Pengiriman khusus</option></select></label><label>Catatan (opsional)<input value={overrideNote} onChange={e=>setOverrideNote(e.target.value)} placeholder="Contoh: Libur pondok / pengganti jadwal"/></label><button className="primary" disabled={overrideBusy}>{overrideBusy?'Menyimpan…':'Simpan tanggal khusus'}</button></form><div className="category-admin-list">{dateOverrides.length===0?<p className="muted">Belum ada tanggal khusus.</p>:dateOverrides.map(row=><div className="category-admin-row" key={row.delivery_date}><div><strong>{new Date(`${row.delivery_date}T00:00:00`).toLocaleDateString('id-ID',{weekday:'long',day:'numeric',month:'long',year:'numeric'})}</strong><small>{row.is_delivery_day?'Pengiriman khusus':'Libur pengiriman'}{row.note?` · ${row.note}`:''}</small></div><button type="button" onClick={()=>deleteDateOverride(row.delivery_date)}>Hapus</button></div>)}</div><button type="button" onClick={loadDateOverrides}>Muat ulang tanggal</button></div><div className="panel settings-panel"><h2>Pembagian akun kasir</h2><p className="muted">Atur jalur setiap akun kasir di sini. Kasir Putra hanya boleh menerima pesanan Putra; Kasir Putri hanya boleh menerima pesanan Putri.</p><button type="button" onClick={loadCashierAccounts} disabled={cashierAccountsBusy}>{cashierAccountsBusy?'Memuat…':'Muat ulang akun kasir'}</button>{cashierAccounts.length===0?<p className="fine-print">Belum ada akun dengan role cashier. Pastikan role akun sudah diatur di Supabase.</p>:cashierAccounts.map(account=><div className="category-admin-row" key={account.id}><div><strong>{account.full_name||'Kasir tanpa nama'}</strong><small>{account.id}</small></div><select aria-label={`Jalur ${account.full_name||account.id}`} value={normalizeGender(account.cashier_gender)} onChange={e=>saveCashierGender(account.id,e.target.value)}><option value="">Pilih jalur</option><option value="Putra">Kasir Putra</option><option value="Putri">Kasir Putri</option></select></div>)}</div></section>}
    </main><footer><span className="footer-mark">و</span><div><strong>Warung Darul Ilmi</strong><small>v1.2.2 · Operasional, distribusi & laporan</small></div><span className="footer-note">بِسْمِ اللَّهِ</span></footer>
  </div>;
}
function AuthScreen({onClose}) {
  const [email,setEmail]=useState('');const [password,setPassword]=useState('');const [message,setMessage]=useState('');const [busy,setBusy]=useState(false);
  async function submit(e){e.preventDefault();setBusy(true);setMessage('');if(!supabase){setMessage('Supabase belum dikonfigurasi.');setBusy(false);return;}const {error}=await supabase.auth.signInWithPassword({email:email.trim(),password});if(error)setMessage(error.message);else onClose?.();setBusy(false);}
  return <div className="auth-screen"><form className="auth-card" onSubmit={submit}><button className="auth-close" type="button" onClick={onClose}>← Kembali ke katalog</button><div className="brand-mark">و</div><p className="eyebrow">AREA KHUSUS PETUGAS</p><h1>Login kasir & admin</h1><p className="auth-description">Pelanggan tidak perlu login. Halaman ini hanya untuk petugas.</p><label>Email<input type="email" autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)} required/></label><label>Password<input type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} required/></label>{message&&<div className="auth-message" role="status">{message}</div>}<button className="primary full" type="submit" disabled={busy}>{busy?'Memproses…':'Masuk'}</button></form></div>;
}
function OrderList({orders,onStatus}) {
  if(!orders.length)return <div className="panel empty">Belum ada pesanan di database.</div>;
  const nextSteps = { pending:['confirmed','cancelled'], confirmed:['preparing','cancelled'], preparing:['ready','cancelled'], ready:['delivered','cancelled'], delivered:[], cancelled:[] };
  return <div className="order-list">{orders.map(o=>{
    const options = [o.status, ...(nextSteps[o.status] || [])];
    return <article className="panel order-card" key={o.id}><div className="order-top"><div><span className="category-label">{o.number}</span><h3>{o.customer.name}</h3><small>{new Date(o.createdAt).toLocaleString('id-ID')}</small></div><span className={`status ${o.status==='delivered'?'paid':''}`}>{statusLabels[o.status]||o.status}</span></div><div className="order-meta"><span>{o.customer.gender}</span><span>{o.customer.dorm}</span><span>{o.customer.className}</span><span>Kirim: {o.deliveryDate}</span></div>{o.note&&<p className="fine-print">Catatan: {o.note}</p>}<div className="order-items">{o.items.map((x,i)=><div key={`${x.id}-${i}`}><span>{x.name} × {x.qty}</span><strong>{money(x.price*x.qty)}</strong></div>)}</div><div className="order-bottom"><strong>{money(o.total)}</strong><div className="order-actions"><label>Status pesanan<select aria-label={`Status pesanan ${o.number}`} value={o.status} onChange={e=>onStatus(o.id,e.target.value)}>{options.map(v=><option key={v} value={v}>{statusLabels[v]}</option>)}</select></label></div></div></article>;
  })}</div>;
}
export default App;

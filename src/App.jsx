import { useEffect, useMemo, useRef, useState } from 'react';
import { isSupabaseConfigured, supabase } from './lib/supabase.js';
import * as XLSX from 'xlsx';

const money = value => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(Number(value || 0));
const statusLabels = { pending: 'Menunggu', confirmed: 'Dikonfirmasi', preparing: 'Diproses', ready: 'Siap diserahkan', delivered: 'Sudah diserahkan', cancelled: 'Dibatalkan' };
const fallbackMenu = [
  { id: 1, name: 'Nasi Ayam', category: 'Makanan', price: 12000, description: 'Contoh produk - ubah melalui database/admin.', emoji: String.fromCodePoint(0x1F357) },
  { id: 2, name: 'Nasi Goreng', category: 'Makanan', price: 10000, description: 'Contoh produk - ubah melalui database/admin.', emoji: String.fromCodePoint(0x1F35B) },
  { id: 3, name: 'Mie Goreng', category: 'Makanan', price: 9000, description: 'Contoh produk - ubah melalui database/admin.', emoji: String.fromCodePoint(0x1F35C) },
  { id: 4, name: 'Es Teh', category: 'Minuman', price: 4000, description: 'Contoh produk - ubah melalui database/admin.', emoji: String.fromCodePoint(0x1F9CB) },
  { id: 5, name: 'Air Mineral', category: 'Minuman', price: 3000, description: 'Contoh produk - ubah melalui database/admin.', emoji: String.fromCodePoint(0x1F4A7) },
  { id: 6, name: 'Roti Cokelat', category: 'Camilan', price: 5000, description: 'Contoh produk - ubah melalui database/admin.', emoji: String.fromCodePoint(0x1F950) }
];
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
function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>\"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[char]));
}
function mapOrder(row) {
  const items = (row.order_items || []).map(x => ({ id: x.product_id ?? x.id, productId: x.product_id ?? null, name: x.product_name_snapshot, price: Number(x.unit_price_snapshot), qty: x.quantity }));
  return { id: row.id, number: row.order_number, createdAt: row.created_at, deliveryDate: row.delivery_date,
    customer: { name: row.guest_name || row.profiles?.full_name || 'Pelanggan', gender: normalizeGender(row.guest_gender), dorm: row.guest_dormitory || '-', className: row.guest_class || '-', phone: row.guest_phone || '' },
    note: row.customer_note || '', items, total: Number(row.total_amount || 0), status: row.status, paymentState: row.payment_state, deletedAt: row.deleted_at, deletedBy: row.deleted_by };
}
function App() {
  const [page, setPage] = useState('order');
  const [products, setProducts] = useState(fallbackMenu);
  const [categories, setCategories] = useState(['Semua','Makanan','Minuman','Camilan']);
  const [cart, setCart] = useState([]);
  const [cartOpen, setCartOpen] = useState(false);
  const [category, setCategory] = useState('Semua');
  const [identity, setIdentity] = useState({ name: '', gender: 'Putra', dorm: '', className: '', phone: '', note: '' });
  const [notice, setNotice] = useState('');
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [staffLoginOpen, setStaffLoginOpen] = useState(false);
  const [databaseStatus, setDatabaseStatus] = useState(isSupabaseConfigured ? 'checking' : 'missing-config');
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
  const [distributionLimitReached, setDistributionLimitReached] = useState(false);  const [search, setSearch] = useState('');
  const [loadingOrders, setLoadingOrders] = useState(false);
  const [orderSubmitting, setOrderSubmitting] = useState(false);
  const [whatsAppFallbackUrl, setWhatsAppFallbackUrl] = useState('');
  const [storeSettings, setStoreSettings] = useState({ store_name: 'Warung Darul Ilmi', brand_logo_url: '', whatsapp_number: '', whatsapp_number_putra: '', whatsapp_number_putri: '', bank_name: '', bank_account_number: '', bank_account_name: '' });
  const [settingsBusy, setSettingsBusy] = useState(false);
  const [settingsPassword, setSettingsPassword] = useState('');
  const [brandLogoFile, setBrandLogoFile] = useState(null);
  const [removeBrandLogo, setRemoveBrandLogo] = useState(false);
  const [menuLoading, setMenuLoading] = useState(false);
  const [deliveryWeekdays, setDeliveryWeekdays] = useState([]);
  const [nextDeliveryDate, setNextDeliveryDate] = useState(null);
  const [scheduleBusy, setScheduleBusy] = useState(false);
  const [dateOverrides, setDateOverrides] = useState([]);
  const [overrideDate, setOverrideDate] = useState('');
  const [overrideDelivery, setOverrideDelivery] = useState(false);
  const [overrideNote, setOverrideNote] = useState('');
  const [overrideBusy, setOverrideBusy] = useState(false);
  const [distributionFrom, setDistributionFrom] = useState('');
  const [distributionTo, setDistributionTo] = useState('');
  const [distributionGender, setDistributionGender] = useState('Semua');  const [adminProducts, setAdminProducts] = useState([]);
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
  const [cashierOrderFrom, setCashierOrderFrom] = useState('');
  const [cashierOrderTo, setCashierOrderTo] = useState('');
  const [trashOrders, setTrashOrders] = useState([]);
  const [trashLoading, setTrashLoading] = useState(false);
  const [showTrash, setShowTrash] = useState(false);
  const [editingOrder, setEditingOrder] = useState(null);
  const [orderEditForm, setOrderEditForm] = useState(null);
  const [orderEditProducts, setOrderEditProducts] = useState([]);
  const [orderEditNewProduct, setOrderEditNewProduct] = useState('');
  const [orderEditBusy, setOrderEditBusy] = useState(false);
  const ordersLoadInFlightRef = useRef(false);
  const ordersRefreshQueuedRef = useRef(false);
  const distributionLoadVersionRef = useRef(0);
  const reportLoadInFlightRef = useRef(false);
  const cashierOrderRangeRef = useRef({ from: '', to: '', enabled: false });
  cashierOrderRangeRef.current = { from: cashierOrderFrom, to: cashierOrderTo, enabled: page === 'cashier' };
  const isStaff = ['cashier','super_admin'].includes(profile?.role);
  const isAdmin = profile?.role === 'super_admin';

  useEffect(() => {
    if (!notice) return undefined;
    const timer = window.setTimeout(() => setNotice(''), 4500);
    return () => window.clearTimeout(timer);
  }, [notice]);

  useEffect(() => {
    if (!supabase) { setAuthLoading(false); setDatabaseStatus('missing-config'); return undefined; }
    let alive = true;
    const timeoutId = window.setTimeout(() => {
      if (alive) { setAuthLoading(false); setNotice('Pemeriksaan sesi membutuhkan waktu terlalu lama. Katalog tetap dapat dibuka; fitur petugas memerlukan koneksi.'); }
    }, 7000);
    supabase.auth.getSession().then(({data,error}) => {
      if (!alive) return;
      if (error) setNotice('Sesi belum dapat diperiksa. Periksa jaringan atau login kembali.');
      setSession(data?.session || null);
    }).catch(() => {
      if (alive) setNotice('Tidak dapat memeriksa sesi karena gangguan jaringan. Katalog tetap dapat dibuka.');
    }).finally(() => {
      if (alive) { window.clearTimeout(timeoutId); setAuthLoading(false); }
    });
    const { data: listener } = supabase.auth.onAuthStateChange((_event,next) => {
      if (!alive) return; setSession(next); setProfile(null);
    });
    return () => { alive = false; window.clearTimeout(timeoutId); listener.subscription.unsubscribe(); };
  }, []);

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
  useEffect(() => {
    let alive = true;
    async function loadProfile() {
      if (!session?.user?.id || !supabase) { setProfile(null); return; }
      const {data,error} = await supabase.from('profiles').select('id,full_name,role,cashier_gender').eq('id',session.user.id).single();
      if (alive) setProfile(error ? null : data);
    }
    loadProfile();
    const refreshProfileOnReturn = async () => {
      const { data } = await supabase.auth.getSession();
      if (alive && data.session?.user?.id === session?.user?.id) loadProfile();
    };
    window.addEventListener('focus', refreshProfileOnReturn);
    document.addEventListener('visibilitychange', refreshProfileOnReturn);
    return () => {
      alive = false;
      window.removeEventListener('focus', refreshProfileOnReturn);
      document.removeEventListener('visibilitychange', refreshProfileOnReturn);
    };
  }, [session?.user?.id]);

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
    setProducts(prods.map(p=>({id:p.id,name:p.name,description:p.description||'',price:Number(p.price),image:p.image_url,category:p.categories?.name||'Lainnya',emoji:String.fromCodePoint(0x1F37D, 0xFE0F)})));
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
  }  useEffect(() => { if (isAdmin && page === 'catalog') loadAdminCatalog(); }, [isAdmin, page]);

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
    if (prods) setProducts(prods.map(p=>({id:p.id,name:p.name,description:p.description||'',price:Number(p.price),image:p.image_url,category:p.categories?.name||'Lainnya',emoji:String.fromCodePoint(0x1F37D, 0xFE0F)})));
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

  async function loadOrders({append = false} = {}) {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return;
    if (ordersLoadInFlightRef.current) {
      ordersRefreshQueuedRef.current = true;
      return;
    }
    const currentRange = cashierOrderRangeRef.current;
    if (currentRange.enabled && currentRange.from && currentRange.to && currentRange.from > currentRange.to) {
      setOrders([]);
      setOrdersHasMore(false);
      return;
    }    if (profile.role === 'cashier' && !normalizeGender(profile.cashier_gender)) {
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
        .is('deleted_at', null)
        .order('created_at',{ascending:false})
        .order('id',{ascending:false})
        .range(from, from + PAGE_SIZE - 1);
      const dateRange = cashierOrderRangeRef.current;
      if (dateRange.enabled && dateRange.from) query = query.gte('created_at', localDateStartIso(dateRange.from));
      if (dateRange.enabled && dateRange.to) query = query.lt('created_at', localDateStartIso(dateRange.to, 1));
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
    if (page === 'cashier' && isStaff) loadOrders();
    else if (page !== 'cashier' && (cashierOrderFrom || cashierOrderTo)) loadOrders();
  }, [cashierOrderFrom, cashierOrderTo, page, profile?.id, profile?.role]);  useEffect(() => {
    if (page === 'cashier' && isStaff) loadTrashOrders();
  }, [page, profile?.id, profile?.role, profile?.cashier_gender, ordersRealtimeVersion]);
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
  const cartCount = cart.reduce((s,x)=>s+x.qty,0);
  const cartTotal = cart.reduce((s,x)=>s+x.qty*x.price,0);
  const visibleMenu = useMemo(()=>category==='Semua'?products:products.filter(p=>p.category===category),[category,products]);
  function addToCart(item) { setCart(c=>{const found=c.find(x=>x.id===item.id);return found?c.map(x=>x.id===item.id?{...x,qty:x.qty+1}:x):[...c,{...item,qty:1}];}); setNotice(`${item.name} ditambahkan ke keranjang.`); }
  function changeQty(id,delta) { setCart(c=>c.map(x=>x.id===id?{...x,qty:x.qty+delta}:x).filter(x=>x.qty>0)); }

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

      // RPC create_guest_order returns exactly one row. Reject empty or multiple rows
      // before any order fields are read or the shopping cart is cleared.
      const responseRows = Array.isArray(data)
        ? data
        : (data && typeof data === 'object' ? [data] : []);
      if (responseRows.length !== 1) {
        if (whatsappTab && !whatsappTab.closed) whatsappTab.close();
        setNotice('Respons server tidak valid: detail pesanan kosong atau berjumlah lebih dari satu. Pesanan mungkin sudah tersimpan. Jangan kirim ulang dulu; periksa antrean kasir atau hubungi admin.');
        return;
      }

      const result = responseRows[0];
      const orderIdValid = typeof result?.order_id === 'string'
        && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result.order_id);
      const orderNumberValid = typeof result?.order_number === 'string'
        && result.order_number.trim().length > 0;
      const deliveryDateText = typeof result?.delivery_date === 'string' ? result.delivery_date : '';
      const deliveryDateValid = /^\d{4}-\d{2}-\d{2}$/.test(deliveryDateText)
        && !Number.isNaN(Date.parse(`${deliveryDateText}T00:00:00Z`))
        && new Date(`${deliveryDateText}T00:00:00Z`).toISOString().slice(0, 10) === deliveryDateText;
      const totalValue = (typeof result?.total_amount === 'number' || typeof result?.total_amount === 'string')
        && String(result.total_amount).trim() !== ''
        ? Number(result.total_amount)
        : Number.NaN;
      const totalValid = Number.isSafeInteger(totalValue) && totalValue >= 0;

      if (!orderIdValid || !orderNumberValid || !deliveryDateValid || !totalValid) {
        if (whatsappTab && !whatsappTab.closed) whatsappTab.close();
        setNotice('Respons server belum lengkap atau formatnya tidak valid. Pesanan mungkin sudah tersimpan. Jangan kirim ulang dulu; periksa antrean kasir menggunakan nama dan waktu pemesanan, atau hubungi admin.');
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
      if (page === 'distribution') await loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo);
    } catch (error) {
      setNotice(`Pesanan gagal diperbarui: ${error?.message || 'Kesalahan jaringan.'}`);
    } finally {
      setOrderEditBusy(false);
    }
  }
  async function updateOrder(id,patch) {
    if (!supabase) return;
    const target = orders.find(o => o.id === id) || reportOrders.find(o => o.id === id) || distributionRows.find(o => o.id === id);
    if (!target) { setNotice('Pesanan tidak ditemukan pada antrean yang sedang dibuka. Muat ulang data.'); return; }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin untuk mengubah pesanan dari jalur lain.'); return;
    }

    try {
      // Cancellation is an atomic database action: status=cancelled and deleted_at set together.
      if (patch.status === 'cancelled') {
        const { error: cancelError } = await supabase.rpc('cancel_staff_order', { p_order_id: id });
        if (cancelError) throw cancelError;

        setNotice(`Pesanan ${target.number} dibatalkan dan dipindahkan ke Sampah. Pesanan dapat dipulihkan selama 3 hari.`);
        const refreshTasks = [loadOrders(), loadTrashOrders()];
        if (page === 'reports' && reportLoaded) refreshTasks.push(loadReportOrders());
        if (page === 'distribution') refreshTasks.push(loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo));
        await Promise.all(refreshTasks);
        return;
      }

      const {data:updatedOrder,error}=await supabase
        .from('orders')
        .update(patch)
        .eq('id',id)
        .select('id,status')
        .maybeSingle();

      if (error) {
        setNotice(`Perubahan gagal disimpan: ${error.message}`);
        return;
      }

      if (!updatedOrder || updatedOrder.id !== id) {
        setNotice('Perubahan tidak terkonfirmasi: baris pesanan tidak ditemukan atau tidak dapat diakses. Muat ulang antrean sebelum mencoba lagi.');
        await loadOrders();
        return;
      }

      if (patch.status !== undefined && updatedOrder.status !== patch.status) {
        setNotice(`Perubahan tidak terkonfirmasi: server mengembalikan status "${updatedOrder.status}" yang berbeda dari permintaan. Muat ulang antrean untuk memeriksa status terbaru.`);
        await loadOrders();
        return;
      }

      setNotice('Perubahan pesanan tersimpan dan telah diverifikasi dari database.');
      await loadOrders();
      if (page === 'reports' && reportLoaded) await loadReportOrders();
      if (page === 'distribution') await loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo);
    } catch (error) {
      setNotice(`Perubahan pesanan gagal dipastikan: ${error?.message || 'Kesalahan jaringan.'}. Muat ulang antrean untuk memeriksa status terbaru.`);
    }
  }

  async function softDeleteOrder(id) {
    if (!supabase || !isStaff) return;
    // Pesanan bisa berasal dari antrean Kasir, Laporan, atau Distribusi.
    const target = [orders, reportOrders, distributionRows]
      .flat()
      .find(order => order.id === id);
    if (!target) {
      setNotice('Pesanan tidak ditemukan pada daftar aktif. Muat ulang data lalu coba kembali.');
      return;
    }
    if (profile?.role === 'cashier' && target.customer.gender !== normalizeGender(profile.cashier_gender)) {
      setNotice('Akun kasir tidak memiliki izin menghapus pesanan dari jalur lain.');
      return;
    }
    try {
      const { error } = await supabase.rpc('soft_delete_staff_order', { p_order_id: id });
      if (error) throw error;
      setNotice(`Pesanan ${target.number} dipindahkan ke Sampah. Pesanan dapat dipulihkan selama 3 hari.`);
      const refreshTasks = [loadOrders(), loadTrashOrders()];
      if (page === 'reports' && reportLoaded) refreshTasks.push(loadReportOrders());
      if (page === 'distribution') refreshTasks.push(loadDistributionOrders(effectiveDistributionFrom, effectiveDistributionTo));
      await Promise.all(refreshTasks);
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
    e.preventDefault();
    if (!supabase) { setNotice('Supabase belum dikonfigurasi. Pengaturan tidak disimpan.'); return; }
    if (!settingsPassword) { setNotice('Masukkan password untuk mengonfirmasi perubahan pengaturan.'); return; }
    setSettingsBusy(true);
    try {
      const { data: functionData, error } = await supabase.functions.invoke('update-store-settings', {
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
      if (error) throw error;
      if (functionData?.success !== true) throw new Error(functionData?.error || 'Server tidak mengonfirmasi penyimpanan.');

      const { data: refreshedSettings, error: refreshError } = await supabase
        .from('store_settings').select('*').eq('id', true).maybeSingle();
      if (refreshError) throw new Error(`Pengaturan tersimpan, tetapi gagal membaca ulang data: ${refreshError.message}`);
      if (!refreshedSettings) throw new Error('Server tidak mengembalikan data pengaturan setelah penyimpanan. Muat ulang halaman untuk memeriksa hasilnya.');

      setStoreSettings(current => ({ ...current, ...refreshedSettings }));
      setBrandLogoFile(null);
      setRemoveBrandLogo(false);
      setSettingsPassword('');
      setNotice('Pengaturan toko dan logo berhasil disimpan dan sudah diverifikasi ulang dari database.');
    } catch (error) {
      const detail = error?.context?.status ? ` (HTTP ${error.context.status})` : '';
      setNotice(`Pengaturan gagal dipastikan tersimpan${detail}: ${error?.message || 'Kesalahan jaringan atau server.'}. Periksa koneksi, status Edge Function, lalu muat ulang data sebelum mencoba lagi.`);
    } finally {
      setSettingsBusy(false);
      setSettingsPassword('');
    }
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
  const invalidCashierOrderRange = Boolean(cashierOrderFrom && cashierOrderTo && cashierOrderFrom > cashierOrderTo);
  const filteredOrders = scopedOrders.filter(o => (effectiveCashierGenderFilter==='Semua'||o.customer.gender===effectiveCashierGenderFilter) && `${o.number} ${o.customer.name} ${o.customer.dorm} ${o.customer.className}`.toLowerCase().includes(search.trim().toLowerCase()));
  const availableDeliveryDates = [...new Set(scopedOrders.map(o=>o.deliveryDate).filter(Boolean))].sort();
  const suggestedDistributionDate = availableDeliveryDates.find(d=>d >= new Date().toISOString().slice(0,10)) || availableDeliveryDates.at(-1) || nextDeliveryDate || new Date().toISOString().slice(0,10);
  const effectiveDistributionFrom = distributionFrom || suggestedDistributionDate;
  const effectiveDistributionTo = distributionTo || effectiveDistributionFrom;
  const invalidDistributionRange = Boolean(effectiveDistributionFrom && effectiveDistributionTo && effectiveDistributionFrom > effectiveDistributionTo);
  const effectiveDistributionGender = profile?.role === 'cashier' ? cashierGender : distributionGender;
  const distributionOrders = distributionRows.filter(o => !effectiveDistributionGender || effectiveDistributionGender === 'Semua' || o.customer.gender === effectiveDistributionGender);
  const distributionGroups = Object.values(distributionOrders.reduce((acc, order) => { const key = `${order.deliveryDate}::${order.customer.gender}::${order.customer.dorm || 'Tanpa asrama'}`; (acc[key] ||= []).push(order); return acc; }, {})).sort((a,b) => `${a[0].deliveryDate}-${a[0].customer.gender}-${a[0].customer.dorm}`.localeCompare(`${b[0].deliveryDate}-${b[0].customer.gender}-${b[0].customer.dorm}`,'id'));
  const invalidReportRange = Boolean(reportFrom && reportTo && reportFrom > reportTo);

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
          .is('deleted_at', null)
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
  }  async function loadCashierAccounts() {
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
    if (reportLoading || !reportLoaded) { setNotice('Muat laporan berdasarkan rentang tanggal terlebih dahulu sebelum mengekspor.'); return; }
    if (reportLimitReached) { setNotice('Laporan belum lengkap karena mencapai batas 50.000 transaksi. Persempit rentang tanggal sebelum mengekspor.'); return; }
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
      const matrixHeaders = ['Nama Santri', 'Kelas', 'Asrama', ...productNames];
      const matrixRows = [matrixHeaders];
      for (const order of reportOrders) {
        const quantities = new Map();
        for (const item of order.items) {
          const key = productKey(item.name);
          if (key) quantities.set(key, (quantities.get(key) || 0) + Number(item.qty || 0));
        }
        matrixRows.push([
          order.customer.name || '', order.customer.className || '', order.customer.dorm || '',
          ...productNames.map(name => quantities.get(productKey(name)) || 0)
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
        const menu = order.items
          .map(item => `${escapeHtml(item.name)} x ${Number(item.qty)}`)
          .join('<br>');
        return `<tr>
          <td>${escapeHtml(order.customer.name)}</td>
          <td>${escapeHtml(order.customer.className)}</td>
          <td>${escapeHtml(order.customer.dorm)}</td>
          <td class="menu-cell">${menu}</td>
          <td class="check-cell"><span class="check-box" aria-label="Belum dicek"></span></td>
        </tr>`;
      }).join('');
      return `<section class="gender-section">
        <h2>Santri ${gender}</h2>
        <table>
          <colgroup>
            <col class="col-name"><col class="col-class"><col class="col-dorm">
            <col class="col-menu"><col class="col-check">
          </colgroup>
          <thead><tr>
            <th>Nama santri</th><th>Kelas</th><th>Asrama</th>
            <th>Menu dan jumlah</th><th>Ceklis</th>
          </tr></thead>
          <tbody>${body}</tbody>
        </table>
      </section>`;
    }).join('');

    // HTML ini hanya berisi dokumen ceklis, tanpa komponen halaman aplikasi.
    // Preview ditampilkan terlebih dahulu; pengguna menekan tombol cetak secara langsung.
    const html = `<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Warung Darul Ilmi â€“ Ceklis Distribusi</title>
<style>
  *{box-sizing:border-box}
  html,body{margin:0;padding:0;background:#fff;color:#17251e}
  body{font:10pt/1.35 Arial,Helvetica,sans-serif}
  .document{width:100%;max-width:190mm;margin:0 auto;padding:0}
  .toolbar{display:flex;justify-content:flex-end;gap:8px;margin:0 auto 14px;max-width:190mm}
  .print-button{border:0;border-radius:8px;padding:11px 16px;background:#174737;color:#fff;font:700 14px Arial,sans-serif;cursor:pointer}
  h1{font-size:17pt;line-height:1.2;margin:0 0 5px;font-weight:700}
  .period{margin:0 0 18px;color:#4f5d55;font-size:9pt}
  .gender-section{margin:17px 0 22px}
  h2{font-size:12pt;margin:0 0 8px;padding:0 5px;break-after:avoid-page;page-break-after:avoid}
  table{width:100%;border-collapse:collapse;table-layout:fixed}
  col.col-name{width:23%} col.col-class{width:12%} col.col-dorm{width:16%}
  col.col-menu{width:39%} col.col-check{width:10%}
  th,td{border:1px solid #9eaaa2;padding:7px 6px;text-align:left;vertical-align:middle;overflow-wrap:anywhere}
  th{background:#f2f4f1;font-weight:700}
  td.menu-cell{line-height:1.55}
  th:last-child,td.check-cell{text-align:center}
  .check-box{display:inline-block;width:15px;height:19px;border:1.4px solid #26382d;vertical-align:middle}
  tr{break-inside:avoid;page-break-inside:avoid}
  thead{display:table-header-group}
  .empty{padding:12px;border:1px solid #aaa}
  @page{size:A4 portrait;margin:12mm 10mm}
  @media screen{body{padding:12px}.document{max-width:190mm}}
  @media print{
    html,body{width:auto;background:#fff!important}
    body{margin:0;padding:0;-webkit-print-color-adjust:exact;print-color-adjust:exact}
    .toolbar{display:none!important}
    .document{max-width:none;width:100%}
    .gender-section{margin:12px 0 18px}
    h1{font-size:16pt} h2{font-size:11pt} th,td{padding:6px 5px}
  }
</style>
</head>
<body>
  <div class="toolbar">
    <button class="print-button" type="button" onclick="window.print()">Cetak / Simpan sebagai PDF</button>
  </div>
  <main class="document">
    <h1>Warung Darul Ilmi â€“ Ceklis Distribusi</h1>
    <p class="period">Periode: ${escapeHtml(reportPeriodLabel())} | Jumlah pesanan: ${reportOrders.length}</p>
    ${rows || '<p class="empty">Tidak ada pesanan.</p>'}
  </main>
</body>
</html>`;

    // Pop-up dibuka langsung saat klik tombol Ekspor PDF (bukan setelah proses async).
    const printWindow = window.open('', '_blank');
    if (!printWindow) {
      setNotice('Browser memblokir jendela pratinjau. Izinkan pop-up untuk situs Warung Darul Ilmi, lalu tekan Ekspor PDF kembali.');
      return;
    }
    try {
      printWindow.document.open();
      printWindow.document.write(html);
      printWindow.document.close();
      setNotice('Pratinjau ceklis siap. Tekan tombol Cetak / Simpan sebagai PDF pada tab yang terbuka.');
    } catch (error) {
      try { printWindow.close(); } catch {}
      setNotice(`Gagal menyiapkan pratinjau PDF: ${error?.message || error}`);
    }
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
  if (staffLoginOpen) return <AuthScreen onClose={()=>setStaffLoginOpen(false)} />;
  return <div className="app-shell">
    <header className="topbar"><button className="brand" onClick={()=>setPage('order')} aria-label="Ke halaman pemesanan">{storeSettings.brand_logo_url ? <img className="brand-logo-image" src={storeSettings.brand_logo_url} alt="Logo toko" /> : <span className="brand-mark">WD</span>}<span><strong>{storeSettings.store_name || 'Warung Darul Ilmi'}</strong><small>Pesan mudah, berkah insyaallah</small></span></button><nav className="nav"><button className={page==='order'?'active':''} onClick={()=>setPage('order')}>Pemesanan</button>{isStaff&&<><button className={page==='cashier'?'active':''} onClick={()=>setPage('cashier')}>Kasir</button><button className={page==='distribution'?'active':''} onClick={()=>setPage('distribution')}>Distribusi & Dapur</button></>}{isAdmin&&<><button className={page==='admin'?'active':''} onClick={()=>setPage('admin')}>Super Admin</button><button className={page==='reports'?'active':''} onClick={()=>setPage('reports')}>Laporan</button><button className={page==='catalog'?'active':''} onClick={()=>setPage('catalog')}>Kelola Katalog</button><button className={page==='settings'?'active':''} onClick={()=>setPage('settings')}>Pengaturan</button></>}{session&&profile&&<span className="account-chip">{profile.full_name||session.user.email}  |  {profile.role}</span>}{session?<button onClick={async()=>{await supabase.auth.signOut();setProfile(null);setPage('order');}}>Keluar</button>:<button onClick={()=>setStaffLoginOpen(true)}>Login Staf</button>}</nav>
    </header>
    <main className="main">
      {databaseStatus!=='connected'&&<div className={`notice db-status db-${databaseStatus}`} role="status">{databaseStatus==='checking'?'Memeriksa koneksi Supabase...':databaseStatus==='missing-config'?'Supabase belum dikonfigurasi. Isi .env.local terlebih dahulu.':'Koneksi database bermasalah. Periksa URL, publishable key, dan tabel.'}</div>}
      {session&&authLoading&&<div className="notice">Memuat akses petugas...</div>}{session&&!authLoading&&!profile&&<div className="notice">Profil petugas tidak ditemukan atau belum memiliki akses.</div>}{notice&&<div className="notice notice-toast" role="status"><span>{notice}</span><button onClick={()=>setNotice('')} aria-label="Tutup pemberitahuan">x</button></div>}{whatsAppFallbackUrl&&<div className="panel" role="status"><strong>Pesanan sudah tersimpan.</strong><p className="fine-print">Jika tab WhatsApp tidak terbuka otomatis, tekan tombol berikut. WhatsApp akan menampilkan pesan yang sudah disiapkan; Anda tetap perlu menekan Kirim di WhatsApp.</p><button className="primary full" type="button" onClick={()=>window.open(whatsAppFallbackUrl,'_blank','noopener,noreferrer')}>Buka WhatsApp untuk mengirim pesanan</button><button type="button" onClick={()=>setWhatsAppFallbackUrl('')}>Tutup pemberitahuan WhatsApp</button></div>}
      {page==='order'&&<section>
        <div className="hero"><div className="hero-pattern">*</div><p className="eyebrow">SELAMAT DATANG</p><h1>Pesan kebutuhanmu<br/><em>dengan mudah.</em></h1><p className="hero-copy">Pilih menu, periksa pesanan, lalu konfirmasi melalui WhatsApp.</p><div className="hero-meta"><span>Praktis</span><span>Tertata</span><span>Mudah dikonfirmasi</span></div></div>
        <div className="section-heading"><div><p className="eyebrow">LANGKAH 01</p><h2>Identitas santri</h2><p className="muted">Data ini membantu petugas mengantarkan pesanan ke tempat yang tepat.</p></div></div>
        <div className="panel identity-grid"><label>Nama santri<input value={identity.name} onChange={e=>setIdentity({...identity,name:e.target.value})} placeholder="Masukkan nama lengkap" required/></label><label>Kategori<select value={identity.gender} onChange={e=>setIdentity({...identity,gender:e.target.value,dorm:''})}><option>Putra</option><option>Putri</option></select></label><label>Asrama<input value={identity.dorm} onChange={e=>setIdentity({...identity,dorm:e.target.value})} placeholder="Nama asrama" required/></label><label>Kelas<input value={identity.className} onChange={e=>setIdentity({...identity,className:e.target.value})} placeholder="Contoh: 8 MTs" required/></label><label>Nomor WhatsApp (opsional)<input inputMode="tel" value={identity.phone} onChange={e=>setIdentity({...identity,phone:e.target.value})} placeholder="08xxxxxxxxxx"/></label><div className="wide delivery-auto"><strong>Jadwal pengiriman otomatis</strong><span>{nextDeliveryDate ? `Perkiraan pengiriman berikutnya: ${new Date(`${nextDeliveryDate}T00:00:00`).toLocaleDateString('id-ID',{weekday:'long',day:'numeric',month:'long',year:'numeric'})}` : 'Tanggal ditentukan otomatis oleh jadwal admin.'}</span></div></div>
        {(storeSettings.bank_name||storeSettings.bank_account_number||storeSettings.payment_instructions)&&<div className="panel payment-info"><strong>Informasi pembayaran</strong><p>{storeSettings.bank_name||'Bank'}  |  {storeSettings.bank_account_number||'Nomor rekening belum diatur'}</p><p>Atas nama: {storeSettings.bank_account_name||'Belum diatur'}</p>{storeSettings.payment_instructions&&<small>{storeSettings.payment_instructions}</small>}</div>}
        <div className="section-heading menu-heading"><div><p className="eyebrow">LANGKAH 02</p><h2>Pilih menu</h2><p className="muted">Produk dan harga dibaca dari katalog Supabase.</p></div><span className="cart-pill">{String.fromCodePoint(0x1F6D2)} {cartCount} item</span></div>
        <div className="chips">{categories.map(c=><button key={c} className={category===c?'selected':''} onClick={()=>setCategory(c)}>{c}</button>)}</div>
        {menuLoading&&<div className="panel">Memuat katalog...</div>}
        <div className="menu-grid">{visibleMenu.map(item=><article className="menu-card" key={item.id}><div className="food-art">{item.image?<><img src={item.image} alt="" loading="lazy" onError={e=>{e.currentTarget.style.display='none';const fallback=e.currentTarget.nextElementSibling;if(fallback)fallback.style.display='grid';}}/><span className="food-art-fallback" aria-hidden="true">{item.emoji||String.fromCodePoint(0x1F37D, 0xFE0F)}</span></>:item.emoji}</div><div className="menu-info"><span className="category-label">{item.category}</span><h3>{item.name}</h3><p>{item.description}</p><div className="menu-bottom"><strong>{money(item.price)}</strong><button onClick={()=>addToCart(item)}>+ Tambah</button></div></div></article>)}</div>
        <div className="section-heading desktop-cart-heading"><div><p className="eyebrow">LANGKAH 03</p><h2>Keranjang pesanan</h2></div></div>
        <div className="panel cart-panel desktop-cart-panel">{cart.length===0?<p className="empty">Keranjang masih kosong. Tambahkan menu pilihanmu.</p>:<>{cart.map(item=><div className="cart-row" key={item.id}><div><strong>{item.name}</strong><small>{money(item.price)} / item</small></div><div className="qty"><button onClick={()=>changeQty(item.id,-1)} aria-label={`Kurangi ${item.name}`}>-</button><b>{item.qty}</b><button onClick={()=>changeQty(item.id,1)} aria-label={`Tambah ${item.name}`}>+</button></div><strong>{money(item.price*item.qty)}</strong></div>)}<label>Catatan untuk dapur/kasir<textarea value={identity.note} onChange={e=>setIdentity({...identity,note:e.target.value})} placeholder="Contoh: sambal dipisah, tanpa sendok plastik"/></label><div className="cart-total"><span>Total pesanan</span><strong>{money(cartTotal)}</strong></div><button className="primary full" onClick={placeOrder} disabled={orderSubmitting}>{orderSubmitting?'Menyimpan pesanan...':'Simpan pesanan & lanjut WhatsApp'} <span>{'→'}</span></button><p className="fine-print">Pesanan disimpan ke Supabase terlebih dahulu. Pembayaran diverifikasi petugas sebelum barang diserahkan.</p></>}</div>
        {cartCount>0&&<div className="mobile-cart-dock"><button type="button" className="mobile-cart-summary" onClick={()=>setCartOpen(true)} aria-expanded={cartOpen} aria-controls="mobile-cart-sheet"><span className="mobile-cart-icon">{String.fromCodePoint(0x1F6D2)} <b>{cartCount}</b></span><span className="mobile-cart-label"><strong>Lihat keranjang</strong><small>{cartCount} item dipilih</small></span><strong className="mobile-cart-total">{money(cartTotal)}</strong><span className="mobile-cart-chevron">^</span></button></div>}
        {cartOpen&&cartCount>0&&<div className="mobile-cart-layer" onClick={()=>setCartOpen(false)}><section id="mobile-cart-sheet" className="mobile-cart-sheet" role="dialog" aria-modal="true" aria-labelledby="mobile-cart-title" onClick={e=>e.stopPropagation()}><div className="mobile-cart-sheet-head"><div><p className="eyebrow">LANGKAH 03</p><h2 id="mobile-cart-title">Keranjang pesanan</h2></div><button type="button" className="mobile-cart-close" onClick={()=>setCartOpen(false)} aria-label="Tutup keranjang">x</button></div><div className="mobile-cart-items">{cart.map(item=><div className="cart-row" key={item.id}><div><strong>{item.name}</strong><small>{money(item.price)} / item</small></div><div className="qty"><button onClick={()=>changeQty(item.id,-1)} aria-label={`Kurangi ${item.name}`}>-</button><b>{item.qty}</b><button onClick={()=>changeQty(item.id,1)} aria-label={`Tambah ${item.name}`}>+</button></div><strong>{money(item.price*item.qty)}</strong></div>)}</div><label>Catatan untuk dapur/kasir<textarea value={identity.note} onChange={e=>setIdentity({...identity,note:e.target.value})} placeholder="Contoh: sambal dipisah, tanpa sendok plastik"/></label><div className="cart-total"><span>Total pesanan</span><strong>{money(cartTotal)}</strong></div><button className="primary full" onClick={placeOrder} disabled={orderSubmitting}>{orderSubmitting?'Menyimpan pesanan...':'Simpan pesanan & lanjut WhatsApp'} <span>{'→'}</span></button><p className="fine-print">Pesanan disimpan ke Supabase terlebih dahulu. Pembayaran diverifikasi petugas sebelum barang diserahkan.</p></section></div>}
      </section>}
      {page==='cashier'&&isStaff&&<section><div className="page-intro"><p className="eyebrow">AREA OPERASIONAL</p><h1>Antrean Kasir {profile?.role==='cashier'?profile.cashier_gender:'Putra & Putri'}</h1><p className="muted">{profile?.role==='cashier'?`Akses dibatasi untuk pesanan santri ${profile.cashier_gender}.`:'Super Admin dapat memantau seluruh pesanan.'} Pemeriksaan pembayaran dan bukti transfer dilakukan melalui WhatsApp, bukan di aplikasi.</p>{profile?.role==='cashier'&&!['Putra','Putri'].includes(profile.cashier_gender)&&<div className="notice">Akun kasir belum memiliki jalur Putra/Putri. Super Admin harus mengatur kolom cashier_gender pada profil akun.</div>}</div>{!showTrash&&<div className="stats"><div className="stat-card"><small>Menunggu (pesanan dimuat)</small><strong>{scopedOrders.filter(o=>o.status==='pending').length}</strong></div><div className="stat-card"><small>Diproses (pesanan dimuat)</small><strong>{scopedOrders.filter(o=>['confirmed','preparing'].includes(o.status)).length}</strong></div><div className="stat-card"><small>Siap diserahkan (pesanan dimuat)</small><strong>{scopedOrders.filter(o=>o.status==='ready').length}</strong></div></div>}<div className="toolbar cashier-toolbar-top"><h2>{showTrash?'Sampah pesanan':'Antrean pesanan'}</h2><div className="cashier-view-tabs"><button type="button" className={!showTrash?'active':''} onClick={()=>setShowTrash(false)}>Antrean aktif ({orders.length})</button><button type="button" className={showTrash?'active':''} onClick={()=>setShowTrash(true)}>Sampah ({trashOrders.length})</button></div></div><div className="cashier-filters">{!showTrash&&<input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Cari nama, tiket, asrama..."/>}{!showTrash&&<label className="cashier-gender-filter">Jalur pesanan<select aria-label="Filter jalur kasir" value={profile?.role==='cashier'?cashierGender:cashierGenderFilter} onChange={e=>setCashierGenderFilter(e.target.value)} disabled={profile?.role==='cashier'}><option value="Semua">Semua jalur (Putra & Putri)</option><option value="Putra">Khusus Putra</option><option value="Putri">Khusus Putri</option></select>{profile?.role==='cashier'&&<small>Filter dikunci sesuai penugasan akun kasir.</small>}</label>}{!showTrash&&<label className="cashier-date-filter">Dari tanggal pemesanan<input type="date" value={cashierOrderFrom} max={cashierOrderTo || undefined} onChange={e=>setCashierOrderFrom(e.target.value)}/></label>}{!showTrash&&<label className="cashier-date-filter">Sampai tanggal pemesanan<input type="date" value={cashierOrderTo} min={cashierOrderFrom || undefined} onChange={e=>setCashierOrderTo(e.target.value)}/></label>}{!showTrash&&invalidCashierOrderRange&&<span className="fine-print cashier-date-warning">Tanggal mulai tidak boleh melewati tanggal akhir.</span>}{!showTrash&&<button onClick={loadOrders}>Muat ulang</button>}{showTrash&&<button onClick={loadTrashOrders}>Muat ulang Sampah</button>}</div>{!showTrash&&loadingOrders&&<p className="muted">Memuat pesanan...</p>}{showTrash&&trashLoading&&<p className="muted">Memuat Sampah pesanan...</p>}<OrderList orders={showTrash?trashOrders:filteredOrders} onStatus={(id,v)=>updateOrder(id,{status:v})} onEdit={openOrderEditor} onDelete={softDeleteOrder} onRestore={restoreOrder} trashMode={showTrash}/><div className="toolbar"><span className="muted">{showTrash?`Menampilkan ${trashOrders.length} pesanan di Sampah (maksimal 200).`:`Menampilkan ${filteredOrders.length} dari ${orders.length} pesanan yang dimuat.`}</span>{!showTrash&&ordersHasMore&&<button type="button" onClick={()=>loadOrders({append:true})} disabled={loadingOrders||ordersLoadingMore}>{ordersLoadingMore?'Memuat...':'Muat 100 pesanan berikutnya'}</button>}</div></section>}
      {page==='distribution'&&isStaff&&<section><div className="page-intro"><p className="eyebrow">DAPUR & PENYERAHAN</p><h1>Distribusi pesanan</h1><p className="muted">Kelompokkan pesanan berdasarkan tanggal pengiriman, kategori santri, dan asrama. Tanggal otomatis memilih tanggal pengiriman yang memiliki pesanan. Status penyerahan diubah oleh kasir dari halaman antrean. Halaman ini hanya untuk pemantauan distribusi.</p></div><div className="panel distribution-tools"><label>Dari tanggal pengiriman<input type="date" value={effectiveDistributionFrom} onChange={e=>setDistributionFrom(e.target.value)}/></label><label>Sampai tanggal pengiriman<input type="date" value={effectiveDistributionTo} min={effectiveDistributionFrom} onChange={e=>setDistributionTo(e.target.value)}/></label><label>Kategori santri<select value={effectiveDistributionGender} onChange={e=>setDistributionGender(e.target.value)} disabled={profile?.role==='cashier'}>{profile?.role==='super_admin'&&<option>Semua</option>}<option>Putra</option><option>Putri</option></select></label><div className="distribution-actions"><button onClick={()=>loadDistributionOrders(effectiveDistributionFrom,effectiveDistributionTo)} disabled={invalidDistributionRange}>Muat ulang pesanan</button></div></div>{invalidDistributionRange&&<p className="notice">Tanggal mulai tidak boleh melewati tanggal akhir.</p>}{distributionLoading&&<p className="muted">Memuat pesanan pada rentang tanggal pengiriman...</p>}{distributionLimitReached&&<p className="notice">Daftar tanggal ini mencapai batas pemuatan.</p>}<div className="stats"><div className="stat-card"><small>Pesanan pada rentang tanggal</small><strong>{distributionOrders.length}</strong></div><div className="stat-card"><small>Total item</small><strong>{distributionOrders.reduce((n,o)=>n+o.items.reduce((m,i)=>m+i.qty,0),0)}</strong></div><div className="stat-card"><small>Nilai pesanan</small><strong>{money(distributionOrders.reduce((n,o)=>n+o.total,0))}</strong></div></div>{!distributionOrders.length?<div className="panel empty">Belum ada pesanan pada rentang {effectiveDistributionFrom} sampai {effectiveDistributionTo}. Ubah rentang tanggal atau muat ulang pesanan.</div>:distributionGroups.map(group=><div className="distribution-group" key={`${group[0].deliveryDate}-${group[0].customer.gender}-${group[0].customer.dorm}`}><div className="section-heading"><div><p className="eyebrow">KELOMPOK DISTRIBUSI</p><h2>{new Date(`${group[0].deliveryDate}T00:00:00`).toLocaleDateString(`id-ID`,{day:`numeric`,month:`long`,year:`numeric`})} | {group[0].customer.gender} | {group[0].customer.dorm}</h2></div><span className="cart-pill">{group.length} pesanan</span></div>{group.map(o=><article className="panel distribution-card" key={o.id}><div><span className="category-label">{o.number}</span><h3>{o.customer.name}</h3><p className="muted">{o.customer.className}  |  {o.items.reduce((n,i)=>n+i.qty,0)} item  |  {money(o.total)}</p><p className="fine-print">Dipesan: {new Date(o.createdAt).toLocaleString(`id-ID`)} | Pengiriman: {o.deliveryDate}</p><div className="order-items">{o.items.map((i,k)=><div key={k}><span>{i.name}</span><b>x {i.qty}</b></div>)}</div>{o.note&&<p className="fine-print">Catatan dapur: {o.note}</p>}</div><div className="distribution-card-actions"><span className="status">{statusLabels[o.status]||o.status}</span></div></article>)}</div>)}</section>}
      {page==='admin'&&isAdmin&&<section><div className="page-intro"><p className="eyebrow">PUSAT KENDALI</p><h1>Portal Super Admin</h1><p className="muted">Pemantauan gabungan antrean Putra dan Putri.</p></div><div className="stats"><div className="stat-card"><small>Pesanan terbaru dimuat</small><strong>{orders.length}</strong></div><div className="stat-card"><small>Nilai pesanan terbaru dimuat</small><strong>{money(orders.reduce((s,o)=>s+o.total,0))}</strong></div><div className="stat-card"><small>Belum selesai (pesanan dimuat)</small><strong>{orders.filter(o=>!['delivered','cancelled'].includes(o.status)).length}</strong></div></div><div className="split-stats"><div className="panel"><span className="category-label">SANTRI PUTRA</span><h2>{orders.filter(o=>o.customer.gender==='Putra').length}</h2><p className="muted">Pesanan masuk</p></div><div className="panel"><span className="category-label">SANTRI PUTRI</span><h2>{orders.filter(o=>o.customer.gender==='Putri').length}</h2><p className="muted">Pesanan masuk</p></div></div><div className="panel settings-panel"><h2>Laporan dan ekspor Excel</h2><p className="muted">Pilih rentang tanggal pengiriman, lihat transaksi yang masuk dalam periode tersebut, lalu unduh laporan Excel dengan satu baris untuk setiap transaksi santri.</p><button className="primary" type="button" onClick={()=>setPage('reports')}>Buka Laporan -&gt;</button></div></section>}
      {page==='reports'&&isAdmin&&<section><div className="page-intro"><p className="eyebrow">LAPORAN OPERASIONAL</p><h1>Laporan pesanan</h1><p className="muted">Filter berdasarkan tanggal pengiriman dan kategori santri. Excel, PDF ceklis distribusi, dan TXT rekap menu mengikuti filter yang dipilih.</p></div><div className="stats"><div className="stat-card"><small>Transaksi dalam laporan</small><strong>{reportOrders.length}</strong></div><div className="stat-card"><small>Total nilai pesanan</small><strong>{money(reportOrders.reduce((sum,o)=>sum+o.total,0))}</strong></div><div className="stat-card"><small>Jumlah item</small><strong>{reportOrders.reduce((sum,o)=>sum+o.items.reduce((n,i)=>n+Number(i.qty||0),0),0)}</strong></div></div><div className="panel" style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:14,alignItems:'end'}}><label>Dari tanggal pengiriman<input type="date" value={reportFrom} disabled={reportLoading} onChange={e=>{setReportFrom(e.target.value);setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}}/></label><label>Sampai tanggal pengiriman<input type="date" value={reportTo} min={reportFrom||undefined} disabled={reportLoading} onChange={e=>{setReportTo(e.target.value);setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}}/></label><label>Kategori santri<select value={reportGender} disabled={reportLoading} onChange={e=>{setReportGender(e.target.value);setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}}><option value="Semua">Semua (Putra & Putri)</option><option value="Putra">Khusus Putra</option><option value="Putri">Khusus Putri</option></select></label><div style={{display:'flex',gap:8,flexWrap:'wrap'}}><button type="button" onClick={()=>{setReportFrom('');setReportTo('');setReportGender('Semua');setReportOrders([]);setReportLoaded(false);setReportLimitReached(false);}} disabled={reportLoading}>Reset filter</button><button type="button" onClick={loadReportOrders} disabled={reportLoading}>{reportLoading?'Memuat laporan...':'Tampilkan / muat ulang laporan'}</button><button className="primary" type="button" onClick={exportWorkbook} disabled={reportLoading||!reportLoaded||reportLimitReached}>Unduh Excel (.xlsx)</button><button type="button" onClick={exportPdfChecklist} disabled={reportLoading||!reportLoaded||reportLimitReached}>Ekspor PDF (ceklis)</button><button type="button" onClick={exportTxtSummary} disabled={reportLoading||!reportLoaded||reportLimitReached}>Unduh TXT</button></div></div><div className="toolbar"><h2>Daftar transaksi ({reportOrders.length})</h2><span className="muted">{reportFrom||'Awal'} s.d. {reportTo||'Terbaru'}  |  {reportGender==='Semua'?'Putra & Putri':reportGender}</span></div>{invalidReportRange?<div className="panel empty">Tanggal mulai tidak boleh melewati tanggal akhir.</div>:reportLoading?<div className="panel empty">Memuat laporan sesuai rentang tanggal...</div>:!reportLoaded?<div className="panel empty">Pilih minimal satu tanggal, lalu tekan Tampilkan / muat ulang laporan. Riwayat tidak diunduh seluruhnya saat halaman dibuka.</div>:<OrderList orders={reportOrders} onStatus={(id,v)=>updateOrder(id,{status:v})} onEdit={openOrderEditor} onDelete={softDeleteOrder}/>}</section>}
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
          <button className="primary" disabled={catalogBusy}>{catalogBusy?'Menyimpan...':editingProduct?'Simpan perubahan':'Tambah produk'}</button>
        </form>
        <div className="panel settings-panel"><h2>Kategori produk</h2><form className="category-add" onSubmit={addCategory}><input value={categoryName} onChange={e=>setCategoryName(e.target.value)} placeholder="Nama kategori baru" required/><button className="primary" disabled={catalogBusy}>Tambah kategori</button></form><div className="category-admin-list">{adminCategories.map(cat=><div className="category-admin-row" key={cat.id}><div><strong>{cat.name}</strong><small>{cat.is_active?'Aktif':'Nonaktif'}</small></div><button type="button" onClick={()=>toggleCategory(cat)}>{cat.is_active?'Nonaktifkan':'Aktifkan'}</button></div>)}</div></div>
        <div className="toolbar"><h2>Daftar produk ({adminProducts.length})</h2><button onClick={loadAdminCatalog}>Muat ulang</button></div>
        {catalogBusy&&<p className="muted">Memuat katalog...</p>}
        <div className="admin-product-list">{adminProducts.map(product=><article className="panel admin-product-row" key={product.id}><div className="admin-product-image">{product.image_url?<img src={product.image_url} alt=""/>:String.fromCodePoint(0x1F37D, 0xFE0F)}</div><div className="admin-product-detail"><span className="category-label">{product.categories?.name||'Tanpa kategori'}  |  {product.is_available?'Tampil':'Disembunyikan'}</span><h3>{product.name}</h3><p>{product.description||'Tidak ada deskripsi.'}</p><strong>{money(product.price)}</strong></div><div className="admin-product-actions"><button onClick={()=>editProduct(product)}>Edit</button><button onClick={()=>toggleProductAvailability(product)}>{product.is_available?'Sembunyikan':'Tampilkan'}</button></div></article>)}</div>
      </section>}
      {page==='settings'&&isAdmin&&<section><div className="page-intro"><p className="eyebrow">KONFIGURASI</p><h1>Pengaturan pusat</h1><p className="muted">Kelola identitas toko, rekening transfer, dan hari pengiriman.</p></div><form className="panel settings-panel" onSubmit={saveSettings}><h2>Informasi toko & pembayaran</h2><label>Nama warung<input value={storeSettings.store_name||''} onChange={e=>setStoreSettings({...storeSettings,store_name:e.target.value})}/></label>
          <div className="settings-logo-field">
            <label>Logo toko (PNG, JPG, atau WebP)
              <input type="file" accept="image/png,image/jpeg,image/webp" onChange={e=>{const file=e.target.files?.[0];if(!file)return;if(file.size>2*1024*1024){setNotice('Ukuran logo maksimal 2 MB.');e.target.value='';return;}if(!['image/png','image/jpeg','image/webp'].includes(file.type)){setNotice('Format logo harus PNG, JPG, atau WebP.');e.target.value='';return;}const reader=new FileReader();reader.onload=()=>{const dataUrl=String(reader.result||'');const base64=dataUrl.split(',')[1]||'';if(base64)setBrandLogoFile({contentType:file.type,base64,previewUrl:dataUrl});};reader.onerror=()=>setNotice('Gagal membaca file logo.');reader.readAsDataURL(file);setRemoveBrandLogo(false);}}/>
            </label>
            {(brandLogoFile?.previewUrl || (!removeBrandLogo && storeSettings.brand_logo_url)) && <div className="store-logo-preview"><img src={brandLogoFile?.previewUrl || storeSettings.brand_logo_url} alt="Pratinjau logo toko"/><button type="button" onClick={()=>{setBrandLogoFile(null);setRemoveBrandLogo(true);}}>Gunakan logo bawaan</button></div>}
            {!brandLogoFile && !storeSettings.brand_logo_url && !removeBrandLogo && <p className="muted">Belum ada logo khusus. Logo bawaan akan ditampilkan.</p>}
            {removeBrandLogo && <p className="muted">Logo khusus akan dihapus setelah pengaturan disimpan.</p>}
          </div><label>WhatsApp Kasir Putra<input inputMode="numeric" value={storeSettings.whatsapp_number_putra||''} onChange={e=>setStoreSettings({...storeSettings,whatsapp_number_putra:e.target.value})} placeholder="628xxxxxxxxxx"/></label><label>WhatsApp Kasir Putri<input inputMode="numeric" value={storeSettings.whatsapp_number_putri||''} onChange={e=>setStoreSettings({...storeSettings,whatsapp_number_putri:e.target.value})} placeholder="628xxxxxxxxxx"/></label><label>WhatsApp Admin Umum (cadangan)<input inputMode="numeric" value={storeSettings.whatsapp_number||''} onChange={e=>setStoreSettings({...storeSettings,whatsapp_number:e.target.value})} placeholder="628xxxxxxxxxx"/></label><label>Nama bank<input value={storeSettings.bank_name||''} onChange={e=>setStoreSettings({...storeSettings,bank_name:e.target.value})} placeholder="Nama bank"/></label><label>Nomor rekening<input inputMode="numeric" value={storeSettings.bank_account_number||''} onChange={e=>setStoreSettings({...storeSettings,bank_account_number:e.target.value})} placeholder="Nomor rekening"/></label><label>Atas nama<input value={storeSettings.bank_account_name||''} onChange={e=>setStoreSettings({...storeSettings,bank_account_name:e.target.value})} placeholder="Nama pemilik rekening"/></label><label>Instruksi pembayaran<textarea value={storeSettings.payment_instructions||''} onChange={e=>setStoreSettings({...storeSettings,payment_instructions:e.target.value})} placeholder="Cantumkan nominal dan nomor pesanan pada berita transfer."/></label><div className="password-confirm-panel"><label>Password<input type="password" name="settings-password-confirmation-entry" autoComplete="new-password" readOnly onFocus={e=>e.currentTarget.removeAttribute("readonly")} value={settingsPassword} onChange={e=>setSettingsPassword(e.target.value)} required/></label></div><p className="fine-print">Nomor WhatsApp menggunakan kode negara 62 tanpa tanda + atau spasi. Pesanan Putra diarahkan ke Kasir Putra, sedangkan pesanan Putri ke Kasir Putri. Nomor Admin Umum dipakai sebagai cadangan jika nomor kasir terkait belum diisi.</p><button className="primary" disabled={settingsBusy}>{settingsBusy?'Memverifikasi & menyimpan...':'Verifikasi password & simpan pengaturan'}</button></form><div className="panel settings-panel"><h2>Jadwal pengiriman mingguan</h2><p className="muted">Pelanggan akan mendapat tanggal pengiriman aktif terdekat secara otomatis.</p><div className="chips">{['Minggu','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu'].map((day,weekday)=>{const active=deliveryWeekdays.find(x=>x.weekday===weekday)?.is_active||false;return <button type="button" key={day} className={active?'selected':''} onClick={()=>setDeliveryWeekdays(old=>[...old.filter(x=>x.weekday!==weekday),{weekday,is_active:!active}])}>{day} {active?String.fromCharCode(0x2713):'+'}</button>;})}</div><p className="fine-print">Tanggal pengiriman berikutnya: {nextDeliveryDate||'Belum tersedia - aktifkan minimal satu hari.'}</p><button className="primary" type="button" onClick={saveDeliverySchedule} disabled={scheduleBusy}>{scheduleBusy?'Menyimpan...':'Simpan jadwal mingguan'}</button></div><div className="panel settings-panel"><h2>Pengecualian tanggal pengiriman</h2><p className="muted">Tambahkan tanggal libur (tidak ada pengiriman) atau tanggal pengiriman khusus. Aturan tanggal khusus mengesampingkan jadwal mingguan.</p><form className="category-add" onSubmit={saveDateOverride}><label>Tanggal<input type="date" value={overrideDate} min={new Date().toISOString().slice(0,10)} onChange={e=>setOverrideDate(e.target.value)} required/></label><label>Jenis tanggal<select value={overrideDelivery?'delivery':'closed'} onChange={e=>setOverrideDelivery(e.target.value==='delivery')}><option value="closed">Libur / tidak ada pengiriman</option><option value="delivery">Pengiriman khusus</option></select></label><label>Catatan (opsional)<input value={overrideNote} onChange={e=>setOverrideNote(e.target.value)} placeholder="Contoh: Libur pondok / pengganti jadwal"/></label><button className="primary" disabled={overrideBusy}>{overrideBusy?'Menyimpan...':'Simpan tanggal khusus'}</button></form><div className="category-admin-list">{dateOverrides.length===0?<p className="muted">Belum ada tanggal khusus.</p>:dateOverrides.map(row=><div className="category-admin-row" key={row.delivery_date}><div><strong>{new Date(`${row.delivery_date}T00:00:00`).toLocaleDateString('id-ID',{weekday:'long',day:'numeric',month:'long',year:'numeric'})}</strong><small>{row.is_delivery_day?'Pengiriman khusus':'Libur pengiriman'}{row.note?`  |  ${row.note}`:''}</small></div><button type="button" onClick={()=>deleteDateOverride(row.delivery_date)}>Hapus</button></div>)}</div><button type="button" onClick={loadDateOverrides}>Muat ulang tanggal</button></div><div className="panel settings-panel"><h2>Pembagian akun kasir</h2><p className="muted">Atur jalur setiap akun kasir di sini. Kasir Putra hanya boleh menerima pesanan Putra; Kasir Putri hanya boleh menerima pesanan Putri.</p><button type="button" onClick={loadCashierAccounts} disabled={cashierAccountsBusy}>{cashierAccountsBusy?'Memuat...':'Muat ulang akun kasir'}</button>{cashierAccounts.length===0?<p className="fine-print">Belum ada akun dengan role cashier. Pastikan role akun sudah diatur di Supabase.</p>:cashierAccounts.map(account=><div className="category-admin-row" key={account.id}><div><strong>{account.full_name||'Kasir tanpa nama'}</strong><small>{account.id}</small></div><select aria-label={`Jalur ${account.full_name||account.id}`} value={normalizeGender(account.cashier_gender)} onChange={e=>saveCashierGender(account.id,e.target.value)}><option value="">Pilih jalur</option><option value="Putra">Kasir Putra</option><option value="Putri">Kasir Putri</option></select></div>)}</div></section>}
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
            <div className="order-edit-add"><label>Tambah menu aktif<select value={orderEditNewProduct} onChange={event => setOrderEditNewProduct(event.target.value)}><option value="">Pilih menu...</option>{orderEditProducts.map(product => <option key={product.id} value={product.id}>{product.name} – {money(product.price)}</option>)}</select></label><button type="button" onClick={addOrderEditProduct} disabled={!orderEditNewProduct || orderEditBusy}>Tambah menu</button></div>
          </div>
          <div className="order-edit-footer"><span>Perkiraan total: <strong>{money(orderEditForm.items.reduce((sum, item) => sum + Number(orderEditProducts.find(product => String(product.id) === String(item.product_id))?.price ?? item.price ?? 0) * Number(item.quantity || 0), 0))}</strong></span><button className="primary" type="submit" disabled={orderEditBusy}>{orderEditBusy ? 'Menyimpan...' : 'Simpan perubahan pesanan'}</button></div>
        </form>
      </section>
    </div>}    </main><footer><span className="footer-mark">WD</span><div><strong>Warung Darul Ilmi</strong><small>v1.2.6  |  Perbaikan foto katalog</small></div></footer>
  </div>;
}
function AuthScreen({onClose}) {
  const [email,setEmail]=useState('');const [password,setPassword]=useState('');const [message,setMessage]=useState('');const [busy,setBusy]=useState(false);
  async function submit(e){e.preventDefault();setBusy(true);setMessage('');if(!supabase){setMessage('Supabase belum dikonfigurasi.');setBusy(false);return;}const {error}=await supabase.auth.signInWithPassword({email:email.trim(),password});if(error)setMessage(error.message);else onClose?.();setBusy(false);}
  return <div className="auth-screen"><form className="auth-card" onSubmit={submit}><button className="auth-close" type="button" onClick={onClose}>&lt;- Kembali ke katalog</button><div className="brand-mark">WD</div><p className="eyebrow">AREA KHUSUS PETUGAS</p><h1>Login kasir & admin</h1><p className="auth-description">Pelanggan tidak perlu login. Halaman ini hanya untuk petugas.</p><label>Email<input type="email" autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)} required/></label><label>Password<input type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} required/></label>{message&&<div className="auth-message" role="status">{message}</div>}<button className="primary full" type="submit" disabled={busy}>{busy?'Memproses...':'Masuk'}</button></form></div>;
}
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
export default App;

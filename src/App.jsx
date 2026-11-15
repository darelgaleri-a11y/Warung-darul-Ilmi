import { useEffect, useMemo, useState } from 'react';
import { isSupabaseConfigured, supabase } from './lib/supabase.js';
import * as XLSX from 'xlsx';

const money = value => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(Number(value || 0));
const statusLabels = { pending: 'Menunggu', confirmed: 'Dikonfirmasi', preparing: 'Diproses', ready: 'Siap diserahkan', delivered: 'Sudah diserahkan', cancelled: 'Dibatalkan' };
const paymentLabels = { unpaid: 'Belum dibayar', pending_verification: 'Menunggu verifikasi', paid: 'Lunas', rejected: 'Ditolak', refunded: 'Dikembalikan' };
const statusValues = Object.fromEntries(Object.entries(statusLabels).map(([k,v]) => [v,k]));
const paymentValues = Object.fromEntries(Object.entries(paymentLabels).map(([k,v]) => [v,k]));
const fallbackMenu = [
  { id: 1, name: 'Nasi Ayam', category: 'Makanan', price: 12000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '🍗' },
  { id: 2, name: 'Nasi Goreng', category: 'Makanan', price: 10000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '🍛' },
  { id: 3, name: 'Mie Goreng', category: 'Makanan', price: 9000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '🍜' },
  { id: 4, name: 'Es Teh', category: 'Minuman', price: 4000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '🧋' },
  { id: 5, name: 'Air Mineral', category: 'Minuman', price: 3000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '💧' },
  { id: 6, name: 'Roti Cokelat', category: 'Camilan', price: 5000, description: 'Contoh produk — ubah melalui database/admin.', emoji: '🥐' }
];
function mapOrder(row) {
  const items = (row.order_items || []).map(x => ({ id: x.product_id ?? x.id, name: x.product_name_snapshot, price: Number(x.unit_price_snapshot), qty: x.quantity }));
  return { id: row.id, number: row.order_number, createdAt: row.created_at, deliveryDate: row.delivery_date,
    customer: { name: row.guest_name || row.profiles?.full_name || 'Pelanggan', gender: row.guest_gender || 'Putra', dorm: row.guest_dormitory || '-', className: row.guest_class || '-', phone: row.guest_phone || '' },
    note: row.customer_note || '', items, payments: row.payment_records || [], total: Number(row.total_amount || 0), status: row.status, paymentStatus: row.payment_state };
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
  const [storeSettings, setStoreSettings] = useState({ store_name: 'Warung Darul Ilmi', whatsapp_number: '', bank_name: '', bank_account_number: '', bank_account_name: '' });
  const [settingsBusy, setSettingsBusy] = useState(false);
  const [menuLoading, setMenuLoading] = useState(false);
  const [deliveryWeekdays, setDeliveryWeekdays] = useState([]);
  const [nextDeliveryDate, setNextDeliveryDate] = useState(null);
  const [scheduleBusy, setScheduleBusy] = useState(false);
  const [distributionDate, setDistributionDate] = useState(new Date().toISOString().slice(0,10));
  const [distributionGender, setDistributionGender] = useState('Semua');
  const [guestOrder, setGuestOrder] = useState(() => { try { return JSON.parse(localStorage.getItem('wdi_guest_order') || 'null'); } catch { return null; } });
  const [proofBusy, setProofBusy] = useState(false);

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

  async function loadOrders() {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return;
    setLoadingOrders(true);
    const {data,error} = await supabase.from('orders').select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity),payment_records(id,amount,proof_url,status,created_at)').order('created_at',{ascending:false}).limit(300);
    if (error) setNotice(`Gagal memuat pesanan: ${error.message}`);
    else setOrders((data || []).map(mapOrder));
    setLoadingOrders(false);
  }
  useEffect(() => { loadOrders(); }, [profile?.id, profile?.role]);
  useEffect(() => {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return;
    const channel = supabase.channel('wdi-orders-live').on('postgres_changes',{event:'*',schema:'public',table:'orders'},()=>loadOrders()).subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [profile?.id, profile?.role]);

  const cartCount = cart.reduce((s,x)=>s+x.qty,0);
  const cartTotal = cart.reduce((s,x)=>s+x.qty*x.price,0);
  const visibleMenu = useMemo(()=>category==='Semua'?products:products.filter(p=>p.category===category),[category,products]);
  const isStaff = ['cashier','super_admin'].includes(profile?.role);
  const isAdmin = profile?.role === 'super_admin';

  function addToCart(item) { setCart(c=>{const found=c.find(x=>x.id===item.id);return found?c.map(x=>x.id===item.id?{...x,qty:x.qty+1}:x):[...c,{...item,qty:1}];}); setNotice(`${item.name} ditambahkan ke keranjang.`); }
  function changeQty(id,delta) { setCart(c=>c.map(x=>x.id===id?{...x,qty:x.qty+delta}:x).filter(x=>x.qty>0)); }

  async function placeOrder() {
    if (!supabase || databaseStatus !== 'connected') { setNotice('Database belum tersambung. Pesanan belum dikirim. Periksa konfigurasi Supabase.'); return; }
    if (!identity.name.trim() || !identity.dorm || !identity.className) { setNotice('Lengkapi nama, asrama, dan kelas.'); return; }
    if (!cart.length) { setNotice('Keranjang masih kosong.'); return; }
    const payload = cart.map(x=>({product_id:Number(x.id),quantity:x.qty}));
    const accessToken = Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2,'0')).join('');
    const {data,error} = await supabase.rpc('create_guest_order',{
      p_guest_name:identity.name.trim(),p_guest_gender:identity.gender,p_guest_dormitory:identity.dorm,p_guest_class:identity.className,
      p_guest_phone:identity.phone.trim() || null,p_customer_note:identity.note.trim() || null,p_items:payload,p_access_token:accessToken
    });
    if (error) { setNotice(`Pesanan gagal disimpan: ${error.message}. Pastikan migrasi Guest Checkout v2 sudah dijalankan.`); return; }
    const result = Array.isArray(data) ? data[0] : data;
    const items = cart.map(x=>({...x}));
    const savedGuestOrder = { orderId: result.order_id, orderNumber: result.order_number, total: Number(result.total_amount), accessToken };
    setGuestOrder(savedGuestOrder); localStorage.setItem('wdi_guest_order', JSON.stringify(savedGuestOrder));
    const message = ['*PESANAN WARUNG DARUL ILMI*',`Nomor: ${result.order_number}`,`Nama: ${identity.name}`,`Kategori: ${identity.gender}`,`Asrama: ${identity.dorm}`,`Kelas: ${identity.className}`,`Tanggal pengiriman: ${new Date(`${result.delivery_date}T00:00:00`).toLocaleDateString('id-ID',{weekday:'long',day:'numeric',month:'long',year:'numeric'})}`,'', '*Rincian pesanan:*',...items.map(x=>`- ${x.name} x${x.qty} = ${money(x.price*x.qty)}`),`*Total: ${money(result.total_amount)}*`,storeSettings.bank_name?`Bank: ${storeSettings.bank_name}`:'',storeSettings.bank_account_number?`Rekening: ${storeSettings.bank_account_number}`:'',storeSettings.bank_account_name?`Atas nama: ${storeSettings.bank_account_name}`:'',identity.note?`Catatan: ${identity.note}`:'',storeSettings.payment_instructions||'Mohon konfirmasi pembayaran. Barang diserahkan setelah pembayaran diverifikasi.'].filter(Boolean).join('\n');
    setCart([]); setIdentity({name:'',gender:identity.gender,dorm:'',className:'',phone:'',note:''});
    setNotice(`Pesanan ${result.order_number} berhasil tersimpan. Tanggal pengiriman: ${result.delivery_date}.`);
    const wa=(storeSettings.whatsapp_number||'').replace(/\D/g,'');
    if (wa) window.open(`https://wa.me/${wa}?text=${encodeURIComponent(message)}`,'_blank','noopener,noreferrer');
    else setNotice(`Pesanan ${result.order_number} tersimpan online. Admin belum mengisi nomor WhatsApp pada Pengaturan.`);
  }

  async function uploadPaymentProof(file) {
    if (!guestOrder || !supabase || !file) return;
    const allowed = ['image/jpeg','image/png','image/webp','application/pdf'];
    if (!allowed.includes(file.type)) { setNotice('Format bukti harus JPG, PNG, WEBP, atau PDF.'); return; }
    if (file.size > 5 * 1024 * 1024) { setNotice('Ukuran bukti maksimal 5 MB.'); return; }
    setProofBusy(true);
    try {
      const ext = file.name.split('.').pop().toLowerCase().replace(/[^a-z0-9]/g,'') || 'jpg';
      const path = `${guestOrder.orderId}/${guestOrder.accessToken}/${crypto.randomUUID()}.${ext}`;
      const {error: uploadError} = await supabase.storage.from('payment-proofs').upload(path,file,{contentType:file.type,upsert:false});
      if (uploadError) throw uploadError;
      const {error: recordError} = await supabase.from('payment_records').insert({order_id:guestOrder.orderId,amount:guestOrder.total,method:'Transfer bank',proof_url:path,status:'pending_verification'});
      if (recordError) throw recordError;
      setNotice('Bukti transfer berhasil dikirim. Kasir akan memeriksa pembayaran.');
      setGuestOrder(null); localStorage.removeItem('wdi_guest_order');
      await loadOrders();
    } catch (error) { setNotice(`Bukti transfer gagal dikirim: ${error.message}`); }
    finally { setProofBusy(false); }
  }

  async function openPaymentProof(path) {
    const {data,error} = await supabase.storage.from('payment-proofs').createSignedUrl(path,300);
    if (error) { setNotice(`Bukti tidak dapat dibuka: ${error.message}`); return; }
    window.open(data.signedUrl,'_blank','noopener,noreferrer');
  }

  async function updateOrder(id,patch) {
    if (!supabase) return;
    let error = null;
    if (patch.payment_state) {
      const order = orders.find(x => x.id === id);
      const latestPayment = order?.payments?.[0];
      if (latestPayment) { const result = await supabase.from('payment_records').update({status:patch.payment_state,verified_by:profile?.id || null,verified_at:['paid','rejected'].includes(patch.payment_state)?new Date().toISOString():null}).eq('id',latestPayment.id); error = result.error; }
      else { const result = await supabase.from('orders').update(patch).eq('id',id); error = result.error; }
    } else { const result = await supabase.from('orders').update(patch).eq('id',id); error = result.error; }
    if (error) setNotice(`Perubahan gagal disimpan: ${error.message}`); else { setNotice('Perubahan pesanan tersimpan.'); await loadOrders(); }
  }
  async function saveSettings(e) {
    e.preventDefault(); setSettingsBusy(true);
    const {error}=await supabase.from('store_settings').update({store_name:storeSettings.store_name,whatsapp_number:storeSettings.whatsapp_number,bank_name:storeSettings.bank_name,bank_account_number:storeSettings.bank_account_number,bank_account_name:storeSettings.bank_account_name,payment_instructions:storeSettings.payment_instructions}).eq('id',true);
    setSettingsBusy(false); setNotice(error?`Gagal menyimpan: ${error.message}`:'Pengaturan rekening dan toko berhasil disimpan.');
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
  const filteredOrders = orders.filter(o => (filter==='Semua'||(filter==='Putra'||filter==='Putri'?o.customer.gender===filter:o.status===statusValues[filter]||o.paymentStatus===paymentValues[filter])) && `${o.number} ${o.customer.name} ${o.customer.dorm} ${o.customer.className}`.toLowerCase().includes(search.toLowerCase()));
  const distributionOrders = orders.filter(o => o.deliveryDate === distributionDate && o.status !== 'cancelled' && (distributionGender === 'Semua' || o.customer.gender === distributionGender));
  const distributionGroups = Object.values(distributionOrders.reduce((acc, order) => { const key = `${order.customer.gender} · ${order.customer.dorm || 'Tanpa asrama'}`; (acc[key] ||= []).push(order); return acc; }, {}));
  function exportWorkbook() {
    const orderRows = orders.map(o => ({ 'Nomor Pesanan':o.number, 'Tanggal Pesan':new Date(o.createdAt).toLocaleString('id-ID'), 'Tanggal Kirim':o.deliveryDate, 'Nama':o.customer.name, 'Kategori':o.customer.gender, 'Asrama':o.customer.dorm, 'Kelas':o.customer.className, 'WhatsApp':o.customer.phone, 'Total':o.total, 'Status Pesanan':statusLabels[o.status] || o.status, 'Status Pembayaran':paymentLabels[o.paymentStatus] || o.paymentStatus, 'Catatan':o.note }));
    const itemRows = orders.flatMap(o => o.items.map(i => ({ 'Nomor Pesanan':o.number, 'Tanggal Kirim':o.deliveryDate, 'Nama Santri':o.customer.name, 'Kategori':o.customer.gender, 'Asrama':o.customer.dorm, 'Kelas':o.customer.className, 'Produk':i.name, 'Jumlah':i.qty, 'Harga Satuan':i.price, 'Subtotal':i.price*i.qty })));
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(orderRows), 'Pesanan');
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(itemRows), 'Rincian Item');
    XLSX.writeFile(wb, `laporan-warung-darul-ilmi-${new Date().toISOString().slice(0,10)}.xlsx`);
  }
  function printKitchenTickets(list = distributionOrders) {
    if (!list.length) { setNotice('Tidak ada pesanan pada tanggal dan filter tersebut.'); return; }
    const html = list.map(o => `<article class="ticket"><header><b>WARUNG DARUL ILMI</b><strong>${o.number}</strong></header><h2>${o.customer.name}</h2><p>${o.customer.gender} · ${o.customer.dorm} · ${o.customer.className}</p><p><b>Tanggal distribusi:</b> ${o.deliveryDate}</p><hr>${o.items.map(i=>`<div class="item"><span>${i.name}</span><b>× ${i.qty}</b></div>`).join('')}<hr><p><b>Catatan:</b> ${o.note || '—'}</p><footer>Periksa jumlah dan identitas sebelum diserahkan.</footer></article>`).join('');
    const w = window.open('', '_blank', 'width=800,height=700');
    if (!w) { setNotice('Popup diblokir browser. Izinkan popup untuk mencetak tiket.'); return; }
    w.document.write(`<!doctype html><html><head><title>Tiket Dapur</title><style>body{font:14px Arial,sans-serif;color:#111}.ticket{border:1px dashed #555;padding:18px;margin:0 auto 18px;max-width:420px;page-break-inside:avoid}.ticket header,.item{display:flex;justify-content:space-between;gap:15px}.ticket h2{margin:14px 0 4px}.ticket p{margin:6px 0}.ticket footer{margin-top:16px;font-size:11px}@media print{.ticket{page-break-after:always;margin:0 auto;border:1px dashed #555}}</style></head><body>${html}<script>window.onload=()=>window.print()<\/script></body></html>`); w.document.close();
  }

  if (staffLoginOpen) return <AuthScreen onClose={()=>setStaffLoginOpen(false)} />;
  return <div className="app-shell">
    <header className="topbar"><button className="brand" onClick={()=>setPage('order')} aria-label="Ke halaman pemesanan"><span className="brand-mark">و</span><span><strong>Warung Darul Ilmi</strong><small>Pesan mudah, berkah insyaallah</small></span></button>
      <nav className="nav"><button className={page==='order'?'active':''} onClick={()=>setPage('order')}>Pemesanan</button>{isStaff&&<><button className={page==='cashier'?'active':''} onClick={()=>setPage('cashier')}>Kasir</button><button className={page==='distribution'?'active':''} onClick={()=>setPage('distribution')}>Distribusi & Dapur</button></>}{isAdmin&&<><button className={page==='admin'?'active':''} onClick={()=>setPage('admin')}>Super Admin</button><button className={page==='settings'?'active':''} onClick={()=>setPage('settings')}>Pengaturan</button></>}{session&&profile&&<span className="account-chip">{profile.full_name||session.user.email} · {profile.role}</span>}{session?<button onClick={async()=>{await supabase.auth.signOut();setProfile(null);setPage('order');}}>Keluar</button>:<button onClick={()=>setStaffLoginOpen(true)}>Login Staf</button>}</nav>
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
        {guestOrder&&<div className="panel payment-info proof-upload-panel"><p className="eyebrow">KONFIRMASI PEMBAYARAN</p><h2>Pesanan {guestOrder.orderNumber}</h2><p>Unggah bukti transfer untuk total {money(guestOrder.total)}. Bukti hanya dapat dikirim menggunakan akses pesanan ini.</p><label>Foto atau PDF bukti transfer<input type="file" accept="image/jpeg,image/png,image/webp,application/pdf" disabled={proofBusy} onChange={e=>{const f=e.target.files?.[0]; if(f) uploadPaymentProof(f); e.target.value='';}}/></label><small>Maksimal 5 MB · JPG, PNG, WEBP, PDF. Setelah dikirim, tunggu verifikasi kasir.</small><button type="button" onClick={()=>{setGuestOrder(null);localStorage.removeItem('wdi_guest_order');}}>Tutup informasi pesanan</button></div>}
      </section>}
      {page==='cashier'&&isStaff&&<section><div className="page-intro"><p className="eyebrow">AREA OPERASIONAL</p><h1>Antrean Kasir {profile?.role==='cashier'?profile.cashier_gender:'Putra & Putri'}</h1><p className="muted">{profile?.role==='cashier'?`Akses dibatasi untuk pesanan santri ${profile.cashier_gender}.`:'Super Admin dapat memantau seluruh pesanan.'}</p></div><div className="stats"><div className="stat-card"><small>Total pesanan</small><strong>{orders.length}</strong></div><div className="stat-card"><small>Menunggu pembayaran</small><strong>{orders.filter(o=>o.paymentStatus!=='paid').length}</strong></div><div className="stat-card"><small>Sudah lunas</small><strong>{orders.filter(o=>o.paymentStatus==='paid').length}</strong></div></div><div className="toolbar"><h2>Antrean pesanan</h2><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Cari nama, tiket, asrama…"/><select value={filter} onChange={e=>setFilter(e.target.value)}><option>Semua</option><option>Putra</option><option>Putri</option><option>Menunggu</option><option>Dikonfirmasi</option><option>Diproses</option><option>Siap diserahkan</option><option>Sudah diserahkan</option><option>Dibatalkan</option><option>Belum dibayar</option><option>Menunggu verifikasi</option><option>Lunas</option></select><button onClick={loadOrders}>Muat ulang</button></div>{loadingOrders&&<p className="muted">Memuat pesanan…</p>}<OrderList orders={filteredOrders} onStatus={(id,v)=>updateOrder(id,{status:v})} onPayment={(id,v)=>updateOrder(id,{payment_state:v})} onProof={openPaymentProof}/></section>}
      {page==='distribution'&&isStaff&&<section><div className="page-intro"><p className="eyebrow">DAPUR & PENYERAHAN</p><h1>Distribusi pesanan</h1><p className="muted">Kelompokkan pesanan berdasarkan tanggal pengiriman, kategori santri, dan asrama. Cetak tiket untuk petugas dapur.</p></div><div className="panel distribution-tools"><label>Tanggal pengiriman<input type="date" value={distributionDate} onChange={e=>setDistributionDate(e.target.value)}/></label><label>Kategori santri<select value={distributionGender} onChange={e=>setDistributionGender(e.target.value)}><option>Semua</option><option>Putra</option><option>Putri</option></select></label><div className="distribution-actions"><button className="primary" onClick={()=>printKitchenTickets()}>Cetak semua tiket dapur</button><button onClick={loadOrders}>Muat ulang pesanan</button></div></div><div className="stats"><div className="stat-card"><small>Jumlah pesanan</small><strong>{distributionOrders.length}</strong></div><div className="stat-card"><small>Total item</small><strong>{distributionOrders.reduce((n,o)=>n+o.items.reduce((m,i)=>m+i.qty,0),0)}</strong></div><div className="stat-card"><small>Nilai pesanan</small><strong>{money(distributionOrders.reduce((n,o)=>n+o.total,0))}</strong></div></div>{!distributionOrders.length?<div className="panel empty">Belum ada pesanan untuk tanggal tersebut.</div>:distributionGroups.map(group=><div className="distribution-group" key={`${group[0].customer.gender}-${group[0].customer.dorm}`}><div className="section-heading"><div><p className="eyebrow">KELOMPOK DISTRIBUSI</p><h2>{group[0].customer.gender} · {group[0].customer.dorm}</h2></div><span className="cart-pill">{group.length} pesanan</span></div>{group.map(o=><article className="panel distribution-card" key={o.id}><div><span className="category-label">{o.number}</span><h3>{o.customer.name}</h3><p className="muted">{o.customer.className} · {o.items.reduce((n,i)=>n+i.qty,0)} item · {money(o.total)}</p><div className="order-items">{o.items.map((i,k)=><div key={k}><span>{i.name}</span><b>× {i.qty}</b></div>)}</div>{o.note&&<p className="fine-print">Catatan dapur: {o.note}</p>}</div><div className="distribution-card-actions"><span className="status">{statusLabels[o.status]||o.status}</span><button onClick={()=>printKitchenTickets([o])}>Cetak tiket</button><button className="primary" onClick={()=>updateOrder(o.id,{status:'delivered'})} disabled={o.status==='delivered'}>Tandai diserahkan</button></div></article>)}</div>)}</section>}
      {page==='admin'&&isAdmin&&<section><div className="page-intro"><p className="eyebrow">PUSAT KENDALI</p><h1>Portal Super Admin</h1><p className="muted">Pemantauan gabungan antrean Putra dan Putri.</p></div><div className="stats"><div className="stat-card"><small>Jumlah transaksi</small><strong>{orders.length}</strong></div><div className="stat-card"><small>Nilai seluruh pesanan</small><strong>{money(orders.reduce((s,o)=>s+o.total,0))}</strong></div><div className="stat-card"><small>Nilai pesanan lunas</small><strong>{money(orders.filter(o=>o.paymentStatus==='paid').reduce((s,o)=>s+o.total,0))}</strong></div></div><div className="split-stats"><div className="panel"><span className="category-label">SANTRI PUTRA</span><h2>{orders.filter(o=>o.customer.gender==='Putra').length}</h2><p className="muted">Pesanan masuk</p></div><div className="panel"><span className="category-label">SANTRI PUTRI</span><h2>{orders.filter(o=>o.customer.gender==='Putri').length}</h2><p className="muted">Pesanan masuk</p></div></div><div className="toolbar"><h2>Rekap pesanan</h2><button onClick={exportWorkbook}>Ekspor Excel (.xlsx)</button></div><OrderList orders={orders} onStatus={(id,v)=>updateOrder(id,{status:v})} onPayment={(id,v)=>updateOrder(id,{payment_state:v})} onProof={openPaymentProof}/></section>}
      {page==='settings'&&isAdmin&&<section><div className="page-intro"><p className="eyebrow">KONFIGURASI</p><h1>Pengaturan pusat</h1><p className="muted">Kelola identitas toko, rekening transfer, dan hari pengiriman.</p></div><form className="panel settings-panel" onSubmit={saveSettings}><h2>Informasi toko & pembayaran</h2><label>Nama warung<input value={storeSettings.store_name||''} onChange={e=>setStoreSettings({...storeSettings,store_name:e.target.value})}/></label><label>Nomor WhatsApp admin<input inputMode="numeric" value={storeSettings.whatsapp_number||''} onChange={e=>setStoreSettings({...storeSettings,whatsapp_number:e.target.value})} placeholder="628xxxxxxxxxx"/></label><label>Nama bank<input value={storeSettings.bank_name||''} onChange={e=>setStoreSettings({...storeSettings,bank_name:e.target.value})} placeholder="Nama bank"/></label><label>Nomor rekening<input inputMode="numeric" value={storeSettings.bank_account_number||''} onChange={e=>setStoreSettings({...storeSettings,bank_account_number:e.target.value})} placeholder="Nomor rekening"/></label><label>Atas nama<input value={storeSettings.bank_account_name||''} onChange={e=>setStoreSettings({...storeSettings,bank_account_name:e.target.value})} placeholder="Nama pemilik rekening"/></label><label>Instruksi pembayaran<textarea value={storeSettings.payment_instructions||''} onChange={e=>setStoreSettings({...storeSettings,payment_instructions:e.target.value})} placeholder="Cantumkan nominal dan nomor pesanan pada berita transfer."/></label><p className="fine-print">Nomor WhatsApp menggunakan kode negara 62 tanpa tanda + atau spasi.</p><button className="primary" disabled={settingsBusy}>{settingsBusy?'Menyimpan…':'Simpan pengaturan toko'}</button></form><div className="panel settings-panel"><h2>Jadwal pengiriman mingguan</h2><p className="muted">Pelanggan akan mendapat tanggal pengiriman aktif terdekat secara otomatis.</p><div className="chips">{['Minggu','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu'].map((day,weekday)=>{const active=deliveryWeekdays.find(x=>x.weekday===weekday)?.is_active||false;return <button type="button" key={day} className={active?'selected':''} onClick={()=>setDeliveryWeekdays(old=>[...old.filter(x=>x.weekday!==weekday),{weekday,is_active:!active}])}>{day} {active?'✓':'+'}</button>;})}</div><p className="fine-print">Tanggal pengiriman berikutnya: {nextDeliveryDate||'Belum tersedia — aktifkan minimal satu hari.'}</p><button className="primary" type="button" onClick={saveDeliverySchedule} disabled={scheduleBusy}>{scheduleBusy?'Menyimpan…':'Simpan jadwal mingguan'}</button></div><div className="panel"><strong>Akses kasir Putra/Putri</strong><p className="muted">Setiap akun dengan role cashier harus diberi jalur Putra atau Putri. Pembatasan data diterapkan oleh kebijakan keamanan database setelah migration v3 dijalankan.</p></div></section>}
    </main><footer><span className="footer-mark">و</span><div><strong>Warung Darul Ilmi</strong><small>v0.8 · Bukti transfer dan verifikasi pembayaran</small></div><span className="footer-note">بِسْمِ اللَّهِ</span></footer>
  </div>;
}
function AuthScreen({onClose}) {
  const [email,setEmail]=useState('');const [password,setPassword]=useState('');const [message,setMessage]=useState('');const [busy,setBusy]=useState(false);
  async function submit(e){e.preventDefault();setBusy(true);setMessage('');if(!supabase){setMessage('Supabase belum dikonfigurasi.');setBusy(false);return;}const {error}=await supabase.auth.signInWithPassword({email:email.trim(),password});if(error)setMessage(error.message);else onClose?.();setBusy(false);}
  return <div className="auth-screen"><form className="auth-card" onSubmit={submit}><button className="auth-close" type="button" onClick={onClose}>← Kembali ke katalog</button><div className="brand-mark">و</div><p className="eyebrow">AREA KHUSUS PETUGAS</p><h1>Login kasir & admin</h1><p className="auth-description">Pelanggan tidak perlu login. Halaman ini hanya untuk petugas.</p><label>Email<input type="email" autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)} required/></label><label>Password<input type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} required/></label>{message&&<div className="auth-message" role="status">{message}</div>}<button className="primary full" type="submit" disabled={busy}>{busy?'Memproses…':'Masuk'}</button></form></div>;
}
function OrderList({orders,onStatus,onPayment,onProof}) {
  if(!orders.length)return <div className="panel empty">Belum ada pesanan di database.</div>;
  return <div className="order-list">{orders.map(o=><article className="panel order-card" key={o.id}><div className="order-top"><div><span className="category-label">{o.number}</span><h3>{o.customer.name}</h3><small>{new Date(o.createdAt).toLocaleString('id-ID')}</small></div><span className={`status ${o.paymentStatus==='paid'?'paid':''}`}>{paymentLabels[o.paymentStatus]||o.paymentStatus}</span></div><div className="order-meta"><span>{o.customer.gender}</span><span>{o.customer.dorm}</span><span>{o.customer.className}</span><span>Kirim: {o.deliveryDate}</span></div>{o.note&&<p className="fine-print">Catatan: {o.note}</p>}<div className="order-items">{o.items.map((x,i)=><div key={`${x.id}-${i}`}><span>{x.name} × {x.qty}</span><strong>{money(x.price*x.qty)}</strong></div>)}</div>{o.payments?.filter(p=>p.proof_url).map(p=><div className="payment-proof-row" key={p.id}><span>Bukti transfer · {paymentLabels[p.status]||p.status}</span><button type="button" onClick={()=>onProof(p.proof_url)}>Lihat bukti (tautan aman)</button></div>)}<div className="order-bottom"><strong>{money(o.total)}</strong><div className="order-actions"><label>Status pesanan<select aria-label="Status pesanan" value={o.status} onChange={e=>onStatus(o.id,e.target.value)}>{Object.entries(statusLabels).map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label><label>Pembayaran<select aria-label="Status pembayaran" value={o.paymentStatus} onChange={e=>onPayment(o.id,e.target.value)}>{Object.entries(paymentLabels).map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label></div></div></article>)}</div>;
}
export default App;

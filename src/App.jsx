import { useEffect, useMemo, useState } from 'react';
import { isSupabaseConfigured, supabase } from './lib/supabase.js';

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
    note: row.customer_note || '', items, total: Number(row.total_amount || 0), status: row.status, paymentStatus: row.payment_state };
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
      const [{data: settings, error: settingsError}, {data: cats}, {data: prods, error: productError}] = await Promise.all([
        supabase.from('store_settings').select('*').eq('id', true).maybeSingle(),
        supabase.from('categories').select('id,name,sort_order').eq('is_active', true).order('sort_order'),
        supabase.from('products').select('id,name,description,price,image_url,category_id,categories(name)').eq('is_available', true).order('name')
      ]);
      if (!alive) return;
      if (settings) setStoreSettings(s => ({...s, ...settings}));
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
      const {data,error} = await supabase.from('profiles').select('id,full_name,role').eq('id',session.user.id).single();
      if (alive) setProfile(error ? null : data);
    }
    loadProfile(); return () => { alive = false; };
  }, [session?.user?.id]);

  async function loadOrders() {
    if (!supabase || !profile || !['cashier','super_admin'].includes(profile.role)) return;
    setLoadingOrders(true);
    const {data,error} = await supabase.from('orders').select('*,order_items(id,product_id,product_name_snapshot,unit_price_snapshot,quantity)').order('created_at',{ascending:false}).limit(300);
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
    const {data,error} = await supabase.rpc('create_guest_order',{
      p_guest_name:identity.name.trim(),p_guest_gender:identity.gender,p_guest_dormitory:identity.dorm,p_guest_class:identity.className,
      p_guest_phone:identity.phone.trim() || null,p_customer_note:identity.note.trim() || null,p_items:payload
    });
    if (error) { setNotice(`Pesanan gagal disimpan: ${error.message}. Pastikan migrasi Guest Checkout v2 sudah dijalankan.`); return; }
    const result = Array.isArray(data) ? data[0] : data;
    const items = cart.map(x=>({...x}));
    const message = ['*PESANAN WARUNG DARUL ILMI*',`Nomor: ${result.order_number}`,`Nama: ${identity.name}`,`Kategori: ${identity.gender}`,`Asrama: ${identity.dorm}`,`Kelas: ${identity.className}`,`Tanggal pengiriman: ${new Date(`${result.delivery_date}T00:00:00`).toLocaleDateString('id-ID',{weekday:'long',day:'numeric',month:'long',year:'numeric'})}`,'', '*Rincian pesanan:*',...items.map(x=>`- ${x.name} x${x.qty} = ${money(x.price*x.qty)}`),`*Total: ${money(result.total_amount)}*`,identity.note?`Catatan: ${identity.note}`:'','Mohon konfirmasi pembayaran. Barang diserahkan setelah pembayaran diverifikasi.'].filter(Boolean).join('\n');
    setCart([]); setIdentity({name:'',gender:identity.gender,dorm:'',className:'',phone:'',note:''});
    setNotice(`Pesanan ${result.order_number} berhasil tersimpan. Tanggal pengiriman: ${result.delivery_date}.`);
    const wa=(storeSettings.whatsapp_number||'').replace(/\D/g,'');
    if (wa) window.open(`https://wa.me/${wa}?text=${encodeURIComponent(message)}`,'_blank','noopener,noreferrer');
    else setNotice(`Pesanan ${result.order_number} tersimpan online. Admin belum mengisi nomor WhatsApp pada Pengaturan.`);
  }

  async function updateOrder(id,patch) {
    if (!supabase) return;
    const {error}=await supabase.from('orders').update(patch).eq('id',id);
    if (error) setNotice(`Perubahan gagal disimpan: ${error.message}`); else { setNotice('Perubahan pesanan tersimpan.'); await loadOrders(); }
  }
  async function saveSettings(e) {
    e.preventDefault(); setSettingsBusy(true);
    const {error}=await supabase.from('store_settings').update({store_name:storeSettings.store_name,whatsapp_number:storeSettings.whatsapp_number}).eq('id',true);
    setSettingsBusy(false); setNotice(error?`Gagal menyimpan: ${error.message}`:'Pengaturan berhasil disimpan ke Supabase.');
  }
  const filteredOrders = orders.filter(o => (filter==='Semua'||(filter==='Putra'||filter==='Putri'?o.customer.gender===filter:o.status===statusValues[filter]||o.paymentStatus===paymentValues[filter])) && `${o.number} ${o.customer.name} ${o.customer.dorm} ${o.customer.className}`.toLowerCase().includes(search.toLowerCase()));

  if (staffLoginOpen) return <AuthScreen onClose={()=>setStaffLoginOpen(false)} />;
  return <div className="app-shell">
    <header className="topbar"><button className="brand" onClick={()=>setPage('order')} aria-label="Ke halaman pemesanan"><span className="brand-mark">و</span><span><strong>Warung Darul Ilmi</strong><small>Pesan mudah, berkah insyaallah</small></span></button>
      <nav className="nav"><button className={page==='order'?'active':''} onClick={()=>setPage('order')}>Pemesanan</button>{isStaff&&<button className={page==='cashier'?'active':''} onClick={()=>setPage('cashier')}>Kasir</button>}{isAdmin&&<><button className={page==='admin'?'active':''} onClick={()=>setPage('admin')}>Super Admin</button><button className={page==='settings'?'active':''} onClick={()=>setPage('settings')}>Pengaturan</button></>}{session&&profile&&<span className="account-chip">{profile.full_name||session.user.email} · {profile.role}</span>}{session?<button onClick={async()=>{await supabase.auth.signOut();setProfile(null);setPage('order');}}>Keluar</button>:<button onClick={()=>setStaffLoginOpen(true)}>Login Staf</button>}</nav>
    </header>
    <main className="main">
      <div className={`notice db-status db-${databaseStatus}`} role="status">{databaseStatus==='checking'?'Memeriksa koneksi Supabase…':databaseStatus==='connected'?'Terhubung ke Supabase · Katalog dan checkout menggunakan database online.':databaseStatus==='missing-config'?'Supabase belum dikonfigurasi. Isi .env.local terlebih dahulu.':'Koneksi database bermasalah. Periksa URL, publishable key, dan tabel.'}</div>
      {session&&authLoading&&<div className="notice">Memuat akses petugas…</div>}{session&&!authLoading&&!profile&&<div className="notice">Profil petugas tidak ditemukan atau belum memiliki akses.</div>}{notice&&<div className="notice" role="status"><span>{notice}</span><button onClick={()=>setNotice('')} aria-label="Tutup pemberitahuan">×</button></div>}
      {page==='order'&&<section>
        <div className="hero"><div className="hero-pattern">✦</div><p className="eyebrow">SELAMAT DATANG</p><h1>Pesan kebutuhanmu<br/><em>dengan mudah.</em></h1><p className="hero-copy">Pilih menu, periksa pesanan, lalu konfirmasi melalui WhatsApp.</p><div className="hero-meta"><span>✧ Praktis</span><span>✧ Tertata</span><span>✧ Mudah dikonfirmasi</span></div></div>
        <div className="section-heading"><div><p className="eyebrow">LANGKAH 01</p><h2>Identitas santri</h2><p className="muted">Data ini membantu petugas mengantarkan pesanan ke tempat yang tepat.</p></div></div>
        <div className="panel identity-grid"><label>Nama santri<input value={identity.name} onChange={e=>setIdentity({...identity,name:e.target.value})} placeholder="Masukkan nama lengkap" required/></label><label>Kategori<select value={identity.gender} onChange={e=>setIdentity({...identity,gender:e.target.value,dorm:''})}><option>Putra</option><option>Putri</option></select></label><label>Asrama<input value={identity.dorm} onChange={e=>setIdentity({...identity,dorm:e.target.value})} placeholder="Nama asrama" required/></label><label>Kelas<input value={identity.className} onChange={e=>setIdentity({...identity,className:e.target.value})} placeholder="Contoh: 8 MTs" required/></label><label>Nomor WhatsApp (opsional)<input inputMode="tel" value={identity.phone} onChange={e=>setIdentity({...identity,phone:e.target.value})} placeholder="08xxxxxxxxxx"/></label><div className="wide delivery-auto"><strong>Jadwal pengiriman otomatis</strong><span>Tanggal ditentukan oleh aturan jadwal pengiriman di database, bukan dipilih pelanggan.</span></div></div>
        <div className="section-heading menu-heading"><div><p className="eyebrow">LANGKAH 02</p><h2>Pilih menu</h2><p className="muted">Produk dan harga dibaca dari katalog Supabase.</p></div><span className="cart-pill">🛒 {cartCount} item</span></div>
        <div className="chips">{categories.map(c=><button key={c} className={category===c?'selected':''} onClick={()=>setCategory(c)}>{c}</button>)}</div>
        {menuLoading&&<div className="panel">Memuat katalog…</div>}
        <div className="menu-grid">{visibleMenu.map(item=><article className="menu-card" key={item.id}><div className="food-art">{item.image?<img src={item.image} alt={item.name}/>:item.emoji}</div><div className="menu-info"><span className="category-label">{item.category}</span><h3>{item.name}</h3><p>{item.description}</p><div className="menu-bottom"><strong>{money(item.price)}</strong><button onClick={()=>addToCart(item)}>+ Tambah</button></div></div></article>)}</div>
        <div className="section-heading"><div><p className="eyebrow">LANGKAH 03</p><h2>Keranjang pesanan</h2></div></div>
        <div className="panel cart-panel">{cart.length===0?<p className="empty">Keranjang masih kosong. Tambahkan menu pilihanmu.</p>:<>{cart.map(item=><div className="cart-row" key={item.id}><div><strong>{item.name}</strong><small>{money(item.price)} / item</small></div><div className="qty"><button onClick={()=>changeQty(item.id,-1)} aria-label={`Kurangi ${item.name}`}>−</button><b>{item.qty}</b><button onClick={()=>changeQty(item.id,1)} aria-label={`Tambah ${item.name}`}>+</button></div><strong>{money(item.price*item.qty)}</strong></div>)}<label>Catatan untuk dapur/kasir<textarea value={identity.note} onChange={e=>setIdentity({...identity,note:e.target.value})} placeholder="Contoh: sambal dipisah, tanpa sendok plastik"/></label><div className="cart-total"><span>Total pesanan</span><strong>{money(cartTotal)}</strong></div><button className="primary full" onClick={placeOrder}>Simpan pesanan & lanjut WhatsApp <span>→</span></button><p className="fine-print">Pesanan disimpan ke Supabase terlebih dahulu. Pembayaran diverifikasi petugas sebelum barang diserahkan.</p></>}</div>
      </section>}
      {page==='cashier'&&isStaff&&<section><div className="page-intro"><p className="eyebrow">AREA OPERASIONAL</p><h1>Antrean kasir</h1><p className="muted">Pesanan dibaca langsung dari Supabase. Pilih jalur Putra atau Putri.</p></div><div className="stats"><div className="stat-card"><small>Total pesanan</small><strong>{orders.length}</strong></div><div className="stat-card"><small>Menunggu pembayaran</small><strong>{orders.filter(o=>o.paymentStatus!=='paid').length}</strong></div><div className="stat-card"><small>Sudah lunas</small><strong>{orders.filter(o=>o.paymentStatus==='paid').length}</strong></div></div><div className="toolbar"><h2>Antrean pesanan</h2><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Cari nama, tiket, asrama…"/><select value={filter} onChange={e=>setFilter(e.target.value)}><option>Semua</option><option>Putra</option><option>Putri</option><option>Menunggu</option><option>Dikonfirmasi</option><option>Diproses</option><option>Siap diserahkan</option><option>Sudah diserahkan</option><option>Dibatalkan</option><option>Belum dibayar</option><option>Menunggu verifikasi</option><option>Lunas</option></select><button onClick={loadOrders}>Muat ulang</button></div>{loadingOrders&&<p className="muted">Memuat pesanan…</p>}<OrderList orders={filteredOrders} onStatus={(id,v)=>updateOrder(id,{status:v})} onPayment={(id,v)=>updateOrder(id,{payment_state:v})}/></section>}
      {page==='admin'&&isAdmin&&<section><div className="page-intro"><p className="eyebrow">PUSAT KENDALI</p><h1>Portal Super Admin</h1><p className="muted">Pemantauan gabungan antrean Putra dan Putri.</p></div><div className="stats"><div className="stat-card"><small>Jumlah transaksi</small><strong>{orders.length}</strong></div><div className="stat-card"><small>Nilai seluruh pesanan</small><strong>{money(orders.reduce((s,o)=>s+o.total,0))}</strong></div><div className="stat-card"><small>Nilai pesanan lunas</small><strong>{money(orders.filter(o=>o.paymentStatus==='paid').reduce((s,o)=>s+o.total,0))}</strong></div></div><div className="split-stats"><div className="panel"><span className="category-label">SANTRI PUTRA</span><h2>{orders.filter(o=>o.customer.gender==='Putra').length}</h2><p className="muted">Pesanan masuk</p></div><div className="panel"><span className="category-label">SANTRI PUTRI</span><h2>{orders.filter(o=>o.customer.gender==='Putri').length}</h2><p className="muted">Pesanan masuk</p></div></div><div className="toolbar"><h2>Rekap pesanan</h2><button onClick={()=>{const rows=[['Nomor','Nama','Gender','Asrama','Kelas','Tanggal kirim','Total','Status','Pembayaran'],...orders.map(o=>[o.number,o.customer.name,o.customer.gender,o.customer.dorm,o.customer.className,o.deliveryDate,o.total,statusLabels[o.status],paymentLabels[o.paymentStatus]])];const csv='\ufeff'+rows.map(r=>r.map(v=>'"'+String(v??'').replaceAll('"','""')+'"').join(';')).join('\n');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));a.download='rekap-warung-darul-ilmi.csv';a.click();URL.revokeObjectURL(a.href);}}>Ekspor Excel (CSV)</button></div><OrderList orders={orders} onStatus={(id,v)=>updateOrder(id,{status:v})} onPayment={(id,v)=>updateOrder(id,{payment_state:v})}/></section>}
      {page==='settings'&&isAdmin&&<section><div className="page-intro"><p className="eyebrow">KONFIGURASI</p><h1>Pengaturan pusat</h1><p className="muted">Pengaturan rekening dan jadwal pengiriman lanjutan akan disempurnakan setelah skema admin dikonfirmasi.</p></div><form className="panel settings-panel" onSubmit={saveSettings}><label>Nama warung<input value={storeSettings.store_name||''} onChange={e=>setStoreSettings({...storeSettings,store_name:e.target.value})}/></label><label>Nomor WhatsApp admin<input inputMode="numeric" value={storeSettings.whatsapp_number||''} onChange={e=>setStoreSettings({...storeSettings,whatsapp_number:e.target.value})} placeholder="628xxxxxxxxxx"/></label><p className="fine-print">Nomor menggunakan kode negara 62 tanpa tanda + atau spasi.</p><button className="primary" disabled={settingsBusy}>{settingsBusy?'Menyimpan…':'Simpan pengaturan'}</button></form><div className="panel"><strong>Rekening pembayaran & cut-off</strong><p className="muted">Belum diaktifkan pada versi ini karena database v1 belum memiliki kolom rekening dan aturan cut-off. Tidak ada data rekening contoh yang akan ditampilkan sebagai data asli.</p></div></section>}
    </main><footer><span className="footer-mark">و</span><div><strong>Warung Darul Ilmi</strong><small>v0.5 · Integrasi katalog dan pesanan Supabase</small></div><span className="footer-note">بِسْمِ اللَّهِ</span></footer>
  </div>;
}
function AuthScreen({onClose}) {
  const [email,setEmail]=useState('');const [password,setPassword]=useState('');const [message,setMessage]=useState('');const [busy,setBusy]=useState(false);
  async function submit(e){e.preventDefault();setBusy(true);setMessage('');if(!supabase){setMessage('Supabase belum dikonfigurasi.');setBusy(false);return;}const {error}=await supabase.auth.signInWithPassword({email:email.trim(),password});if(error)setMessage(error.message);else onClose?.();setBusy(false);}
  return <div className="auth-screen"><form className="auth-card" onSubmit={submit}><button className="auth-close" type="button" onClick={onClose}>← Kembali ke katalog</button><div className="brand-mark">و</div><p className="eyebrow">AREA KHUSUS PETUGAS</p><h1>Login kasir & admin</h1><p className="auth-description">Pelanggan tidak perlu login. Halaman ini hanya untuk petugas.</p><label>Email<input type="email" autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)} required/></label><label>Password<input type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} required/></label>{message&&<div className="auth-message" role="status">{message}</div>}<button className="primary full" type="submit" disabled={busy}>{busy?'Memproses…':'Masuk'}</button></form></div>;
}
function OrderList({orders,onStatus,onPayment}) {
  if(!orders.length)return <div className="panel empty">Belum ada pesanan di database.</div>;
  return <div className="order-list">{orders.map(o=><article className="panel order-card" key={o.id}><div className="order-top"><div><span className="category-label">{o.number}</span><h3>{o.customer.name}</h3><small>{new Date(o.createdAt).toLocaleString('id-ID')}</small></div><span className={`status ${o.paymentStatus==='paid'?'paid':''}`}>{paymentLabels[o.paymentStatus]||o.paymentStatus}</span></div><div className="order-meta"><span>{o.customer.gender}</span><span>{o.customer.dorm}</span><span>{o.customer.className}</span><span>Kirim: {o.deliveryDate}</span></div>{o.note&&<p className="fine-print">Catatan: {o.note}</p>}<div className="order-items">{o.items.map((x,i)=><div key={`${x.id}-${i}`}><span>{x.name} × {x.qty}</span><strong>{money(x.price*x.qty)}</strong></div>)}</div><div className="order-bottom"><strong>{money(o.total)}</strong><div className="order-actions"><label>Status pesanan<select aria-label="Status pesanan" value={o.status} onChange={e=>onStatus(o.id,e.target.value)}>{Object.entries(statusLabels).map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label><label>Pembayaran<select aria-label="Status pembayaran" value={o.paymentStatus} onChange={e=>onPayment(o.id,e.target.value)}>{Object.entries(paymentLabels).map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label></div></div></article>)}</div>;
}
export default App;

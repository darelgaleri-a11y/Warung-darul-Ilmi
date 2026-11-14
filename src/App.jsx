import { useEffect, useMemo, useState } from 'react';

const STORAGE_KEY = 'wdi-orders-v1';
const SETTINGS_KEY = 'wdi-settings-v1';

// Isi nomor WhatsApp admin dengan kode negara, tanpa tanda + atau spasi.
// Contoh format: 6281234567890. Jangan gunakan nomor contoh sebagai nomor asli.
const WHATSAPP_ADMIN = 'ISI_NOMOR_WHATSAPP_DI_SINI';

const sampleMenu = [
  { id: 1, name: 'Nasi Ayam', category: 'Makanan', price: 12000, description: 'Contoh menu — silakan ganti sesuai daftar warung.', emoji: '🍗' },
  { id: 2, name: 'Nasi Goreng', category: 'Makanan', price: 10000, description: 'Contoh menu — silakan ganti sesuai daftar warung.', emoji: '🍛' },
  { id: 3, name: 'Mie Goreng', category: 'Makanan', price: 9000, description: 'Contoh menu — silakan ganti sesuai daftar warung.', emoji: '🍜' },
  { id: 4, name: 'Es Teh', category: 'Minuman', price: 4000, description: 'Contoh menu — silakan ganti sesuai daftar warung.', emoji: '🧋' },
  { id: 5, name: 'Air Mineral', category: 'Minuman', price: 3000, description: 'Contoh menu — silakan ganti sesuai daftar warung.', emoji: '💧' },
  { id: 6, name: 'Roti Cokelat', category: 'Camilan', price: 5000, description: 'Contoh menu — silakan ganti sesuai daftar warung.', emoji: '🥐' }
];

const money = value => new Intl.NumberFormat('id-ID', {
  style: 'currency', currency: 'IDR', maximumFractionDigits: 0
}).format(value || 0);

function readOrders() {
  try { return JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]'); }
  catch { return []; }
}

function App() {
  const [page, setPage] = useState('order');
  const [orders, setOrders] = useState(readOrders);
  const [cart, setCart] = useState([]);
  const [category, setCategory] = useState('Semua');
  const [identity, setIdentity] = useState({
    name: '', gender: 'Putra', dorm: '', className: '', schedule: ''
  });
  const [notice, setNotice] = useState('');
  const [filter, setFilter] = useState('Semua');
  const [settings, setSettings] = useState(() => {
    try { return JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{"wa":""}'); }
    catch { return { wa: '' }; }
  });

  useEffect(() => localStorage.setItem(STORAGE_KEY, JSON.stringify(orders)), [orders]);
  useEffect(() => localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)), [settings]);

  const cartCount = cart.reduce((sum, item) => sum + item.qty, 0);
  const cartTotal = cart.reduce((sum, item) => sum + item.qty * item.price, 0);
  const visibleMenu = useMemo(() => category === 'Semua'
    ? sampleMenu : sampleMenu.filter(item => item.category === category), [category]);

  function addToCart(menuItem) {
    setCart(current => {
      const found = current.find(item => item.id === menuItem.id);
      return found
        ? current.map(item => item.id === menuItem.id ? { ...item, qty: item.qty + 1 } : item)
        : [...current, { ...menuItem, qty: 1 }];
    });
    setNotice(`${menuItem.name} ditambahkan ke keranjang.`);
  }

  function changeQty(id, delta) {
    setCart(current => current
      .map(item => item.id === id ? { ...item, qty: item.qty + delta } : item)
      .filter(item => item.qty > 0));
  }

  function placeOrder() {
    if (!identity.name.trim() || !identity.dorm || !identity.className || !identity.schedule) {
      setNotice('Lengkapi identitas santri dan jadwal terlebih dahulu.');
      return;
    }
    if (!cart.length) {
      setNotice('Keranjang masih kosong. Pilih menu terlebih dahulu.');
      return;
    }
    const order = {
      id: `WDI-${Date.now().toString().slice(-7)}`,
      createdAt: new Date().toISOString(),
      customer: { ...identity },
      items: cart.map(({ id, name, price, qty }) => ({ id, name, price, qty })),
      total: cartTotal,
      status: 'Menunggu konfirmasi WhatsApp',
      paymentStatus: 'Belum dibayar'
    };
    setOrders(current => [order, ...current]);
    const message = [
      '*PESANAN WARUNG DARUL ILMI*',
      `Nomor: ${order.id}`,
      `Nama santri: ${identity.name}`,
      `Kategori: ${identity.gender}`,
      `Asrama: ${identity.dorm}`,
      `Kelas: ${identity.className}`,
      `Jadwal: ${identity.schedule}`,
      '',
      '*Rincian pesanan:*',
      ...order.items.map(item => `- ${item.name} x${item.qty} = ${money(item.price * item.qty)}`),
      `*Total: ${money(order.total)}*`,
      '',
      'Mohon konfirmasi pesanan dan informasi pembayaran. Pesanan dibayar terlebih dahulu sebelum barang diserahkan.'
    ].join('\n');
    const number = (settings.wa || WHATSAPP_ADMIN).replace(/\D/g, '');
    setCart([]);
    setPage('order');
    if (!number || number === 'ISI_NOMOR_WHATSAPP_DI_SINI') {
      setNotice(`Pesanan ${order.id} tersimpan di perangkat ini. Isi nomor WhatsApp admin di menu Pengaturan untuk mengirim pesanan.`);
      return;
    }
    window.open(`https://wa.me/${number}?text=${encodeURIComponent(message)}`, '_blank', 'noopener,noreferrer');
    setNotice(`Pesanan ${order.id} dibuat. Selesaikan konfirmasi melalui WhatsApp.`);
  }

  function updateStatus(id, status) {
    setOrders(current => current.map(order => order.id === id ? { ...order, status } : order));
  }
  function updatePayment(id, paymentStatus) {
    setOrders(current => current.map(order => order.id === id ? { ...order, paymentStatus } : order));
  }

  const filteredOrders = orders.filter(order => {
    if (filter === 'Semua') return true;
    if (filter === 'Putra' || filter === 'Putri') return order.customer.gender === filter;
    return order.status === filter;
  });

  return <div className="app-shell">
    <header className="topbar">
      <button className="brand" onClick={() => setPage('order')} aria-label="Ke halaman pemesanan">
        <span className="brand-mark">و</span>
        <span><strong>Warung Darul Ilmi</strong><small>Pesan mudah, berkah insyaallah</small></span>
      </button>
      <nav className="nav">
        <button className={page === 'order' ? 'active' : ''} onClick={() => setPage('order')}>Pemesanan</button>
        <button className={page === 'cashier' ? 'active' : ''} onClick={() => setPage('cashier')}>Kasir</button>
        <button className={page === 'admin' ? 'active' : ''} onClick={() => setPage('admin')}>Super Admin</button>
        <button className={page === 'settings' ? 'active' : ''} onClick={() => setPage('settings')}>Pengaturan</button>
      </nav>
    </header>

    <main className="main">
      {notice && <div className="notice" role="status"><span>{notice}</span><button onClick={() => setNotice('')} aria-label="Tutup pemberitahuan">×</button></div>}

      {page === 'order' && <section>
        <div className="hero">
          <div className="hero-pattern">✦</div>
          <p className="eyebrow">SELAMAT DATANG</p>
          <h1>Pesan kebutuhanmu<br/><em>dengan mudah.</em></h1>
          <p className="hero-copy">Pilih menu, periksa pesanan, lalu konfirmasi melalui WhatsApp.</p>
          <div className="hero-meta"><span>✧ Praktis</span><span>✧ Tertata</span><span>✧ Mudah dikonfirmasi</span></div>
        </div>

        <div className="section-heading">
          <div><p className="eyebrow">LANGKAH 01</p><h2>Identitas pemesan</h2></div>
          <span className="step-pill">Data santri</span>
        </div>
        <div className="panel identity-grid">
          <label>Nama santri<input value={identity.name} onChange={e => setIdentity({ ...identity, name: e.target.value })} placeholder="Masukkan nama lengkap" /></label>
          <label>Kategori<select value={identity.gender} onChange={e => setIdentity({ ...identity, gender: e.target.value, dorm: '' })}><option>Putra</option><option>Putri</option></select></label>
          <label>Asrama<select value={identity.dorm} onChange={e => setIdentity({ ...identity, dorm: e.target.value })}><option value="">Pilih asrama</option>{(identity.gender === 'Putra' ? ['Asrama Putra 1', 'Asrama Putra 2'] : ['Asrama Putri 1', 'Asrama Putri 2']).map(x => <option key={x}>{x}</option>)}</select></label>
          <label>Kelas<select value={identity.className} onChange={e => setIdentity({ ...identity, className: e.target.value })}><option value="">Pilih kelas</option>{['Ibtidaiyah', 'Tsanawiyah', 'Aliyah', 'Lainnya'].map(x => <option key={x}>{x}</option>)}</select></label>
          <label className="wide">Jadwal pengiriman<select value={identity.schedule} onChange={e => setIdentity({ ...identity, schedule: e.target.value })}><option value="">Pilih jadwal</option>{['Pagi', 'Siang', 'Sore', 'Malam'].map(x => <option key={x}>{x}</option>)}</select></label>
        </div>

        <div className="section-heading menu-heading">
          <div><p className="eyebrow">LANGKAH 02</p><h2>Pilih menu</h2><p className="muted">Daftar di bawah masih berupa data contoh.</p></div>
          <span className="cart-pill">🛒 {cartCount} item</span>
        </div>
        <div className="chips">{['Semua', 'Makanan', 'Minuman', 'Camilan'].map(item => <button key={item} className={category === item ? 'selected' : ''} onClick={() => setCategory(item)}>{item}</button>)}</div>
        <div className="menu-grid">{visibleMenu.map(item => <article className="menu-card" key={item.id}>
          <div className="food-art">{item.emoji}</div>
          <div className="menu-info"><span className="category-label">{item.category}</span><h3>{item.name}</h3><p>{item.description}</p><div className="menu-bottom"><strong>{money(item.price)}</strong><button onClick={() => addToCart(item)}>+ Tambah</button></div></div>
        </article>)}</div>

        <div className="section-heading"><div><p className="eyebrow">LANGKAH 03</p><h2>Keranjang pesanan</h2></div></div>
        <div className="panel cart-panel">
          {cart.length === 0 ? <p className="empty">Keranjang masih kosong. Tambahkan menu pilihanmu.</p> : <>
            {cart.map(item => <div className="cart-row" key={item.id}><div><strong>{item.name}</strong><small>{money(item.price)} / item</small></div><div className="qty"><button onClick={() => changeQty(item.id, -1)} aria-label={`Kurangi ${item.name}`}>−</button><b>{item.qty}</b><button onClick={() => changeQty(item.id, 1)} aria-label={`Tambah ${item.name}`}>+</button></div><strong>{money(item.price * item.qty)}</strong></div>)}
            <div className="cart-total"><span>Total pesanan</span><strong>{money(cartTotal)}</strong></div>
            <button className="primary full" onClick={placeOrder}>Buat pesanan & lanjut WhatsApp <span>→</span></button>
            <p className="fine-print">Pembayaran dilakukan setelah pemesanan dan harus lunas sebelum barang diserahkan. Konfirmasi detail pembayaran melalui WhatsApp.</p>
          </>}
        </div>
      </section>}

      {page === 'cashier' && <section>
        <div className="page-intro"><p className="eyebrow">AREA OPERASIONAL</p><h1>Dashboard kasir</h1><p className="muted">Kelola antrean pesanan putra dan putri. Data saat ini tersimpan di browser ini.</p></div>
        <div className="stats"><div className="stat-card"><small>Total pesanan</small><strong>{orders.length}</strong></div><div className="stat-card"><small>Menunggu pembayaran</small><strong>{orders.filter(o => o.paymentStatus !== 'Lunas').length}</strong></div><div className="stat-card"><small>Pesanan lunas</small><strong>{orders.filter(o => o.paymentStatus === 'Lunas').length}</strong></div></div>
        <div className="toolbar"><h2>Antrean pesanan</h2><select value={filter} onChange={e => setFilter(e.target.value)}><option>Semua</option><option>Putra</option><option>Putri</option><option>Menunggu konfirmasi WhatsApp</option><option>Diproses</option><option>Siap diambil</option><option>Selesai</option></select></div>
        <OrderList orders={filteredOrders} onStatus={updateStatus} onPayment={updatePayment} />
      </section>}

      {page === 'admin' && <section>
        <div className="page-intro"><p className="eyebrow">PUSAT KENDALI</p><h1>Ringkasan super admin</h1><p className="muted">Rekap gabungan seluruh pesanan yang tersimpan di browser ini.</p></div>
        <div className="stats">
          <div className="stat-card"><small>Jumlah transaksi</small><strong>{orders.length}</strong></div>
          <div className="stat-card"><small>Nilai seluruh pesanan</small><strong>{money(orders.reduce((s,o) => s + o.total, 0))}</strong></div>
          <div className="stat-card"><small>Sudah lunas</small><strong>{money(orders.filter(o => o.paymentStatus === 'Lunas').reduce((s,o) => s + o.total, 0))}</strong></div>
        </div>
        <div className="split-stats"><div className="panel"><span className="category-label">SANTRI PUTRA</span><h2>{orders.filter(o => o.customer.gender === 'Putra').length}</h2><p className="muted">Pesanan masuk</p></div><div className="panel"><span className="category-label">SANTRI PUTRI</span><h2>{orders.filter(o => o.customer.gender === 'Putri').length}</h2><p className="muted">Pesanan masuk</p></div></div>
        <h2 className="subheading">Riwayat transaksi</h2><OrderList orders={orders} onStatus={updateStatus} onPayment={updatePayment} />
      </section>}

      {page === 'settings' && <section>
        <div className="page-intro"><p className="eyebrow">KONFIGURASI</p><h1>Pengaturan aplikasi</h1><p className="muted">Lengkapi nomor WhatsApp tujuan pesanan.</p></div>
        <div className="panel settings-panel">
          <label>Nomor WhatsApp admin<input inputMode="numeric" value={settings.wa} onChange={e => setSettings({ ...settings, wa: e.target.value })} placeholder="Contoh format: 6281234567890" /></label>
          <p className="fine-print">Gunakan kode negara 62, tanpa tanda +, spasi, atau tanda hubung. Nomor ini digunakan untuk membuka WhatsApp dengan rincian pesanan yang sudah terisi.</p>
          <div className="warning">Catatan: versi awal ini belum memakai server/database online. Data pesanan tersimpan hanya di browser/perangkat yang digunakan.</div>
          <button className="primary" onClick={() => setNotice('Pengaturan WhatsApp tersimpan di browser ini.')}>Simpan pengaturan</button>
        </div>
      </section>}
    </main>
    <footer><span className="footer-mark">و</span><div><strong>Warung Darul Ilmi</strong><small>Versi awal · Untuk pengujian lokal</small></div><span className="footer-note">بِسْمِ اللَّهِ</span></footer>
  </div>;
}

function OrderList({ orders, onStatus, onPayment }) {
  if (!orders.length) return <div className="panel empty">Belum ada pesanan. Pesanan baru akan tampil di sini.</div>;
  return <div className="order-list">{orders.map(order => <article className="panel order-card" key={order.id}>
    <div className="order-top"><div><span className="category-label">{order.id}</span><h3>{order.customer.name}</h3><small>{new Date(order.createdAt).toLocaleString('id-ID')}</small></div><span className={`status ${order.paymentStatus === 'Lunas' ? 'paid' : ''}`}>{order.paymentStatus}</span></div>
    <div className="order-meta"><span>{order.customer.gender}</span><span>{order.customer.dorm}</span><span>{order.customer.className}</span><span>{order.customer.schedule}</span></div>
    <div className="order-items">{order.items.map(item => <div key={item.id}><span>{item.name} × {item.qty}</span><strong>{money(item.price * item.qty)}</strong></div>)}</div>
    <div className="order-bottom"><strong>{money(order.total)}</strong><div className="order-actions">
      <select aria-label="Status pesanan" value={order.status} onChange={e => onStatus(order.id, e.target.value)}><option>Menunggu konfirmasi WhatsApp</option><option>Diproses</option><option>Siap diambil</option><option>Selesai</option><option>Dibatalkan</option></select>
      <select aria-label="Status pembayaran" value={order.paymentStatus} onChange={e => onPayment(order.id, e.target.value)}><option>Belum dibayar</option><option>Menunggu verifikasi</option><option>Lunas</option></select>
    </div></div>
  </article>)}</div>;
}

export default App;
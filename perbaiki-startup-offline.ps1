$ErrorActionPreference = 'Stop'
$path = Join-Path (Get-Location) 'src\App.jsx'
if (!(Test-Path $path)) { throw 'src\App.jsx tidak ditemukan. Jalankan dari folder utama proyek.' }
$source = [System.IO.File]::ReadAllText($path)
$backup = "$path.bak-sebelum-fix-startup-offline"
if (Test-Path $backup) { throw "Backup sudah ada: $backup. Periksa dulu sebelum menjalankan ulang." }
$oldAuth = @'
  useEffect(() => {
    if (!supabase) return;
    let alive = true;
    supabase.auth.getSession().then(({data}) => { if (alive) { setSession(data.session); setAuthLoading(false); } });
    const { data: listener } = supabase.auth.onAuthStateChange((_event, next) => { setSession(next); setProfile(null); });
    return () => { alive = false; listener.subscription.unsubscribe(); };
  }, []);
'@
$newAuth = @'
  useEffect(() => {
    if (!supabase) {
      setAuthLoading(false);
      setDatabaseStatus('missing-config');
      return undefined;
    }
    let alive = true;
    const timeoutId = window.setTimeout(() => {
      if (alive) {
        setAuthLoading(false);
        setNotice('Pemeriksaan sesi membutuhkan waktu terlalu lama. Halaman katalog tetap dapat digunakan; fitur petugas memerlukan koneksi.');
      }
    }, 7000);
    supabase.auth.getSession()
      .then(({data, error}) => {
        if (!alive) return;
        if (error) setNotice('Sesi belum dapat diperiksa. Silakan muat ulang atau login kembali saat jaringan tersedia.');
        setSession(data?.session || null);
      })
      .catch(() => {
        if (alive) setNotice('Tidak dapat memeriksa sesi karena gangguan jaringan. Katalog tetap dapat dibuka.');
      })
      .finally(() => {
        if (alive) {
          window.clearTimeout(timeoutId);
          setAuthLoading(false);
        }
      });
    const { data: listener } = supabase.auth.onAuthStateChange((_event, next) => {
      if (!alive) return;
      setSession(next);
      setProfile(null);
    });
    return () => {
      alive = false;
      window.clearTimeout(timeoutId);
      listener.subscription.unsubscribe();
    };
  }, []);
'@
$oldInit = @'
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
      if (!settingsError) setNotice('Terhubung ke Supabase · Katalog dan checkout menggunakan database online.');
      setMenuLoading(false);
    })();
    return () => { alive = false; };
  }, []);
'@
$newInit = @'
  useEffect(() => {
    let alive = true;
    if (!supabase) {
      setDatabaseStatus('missing-config');
      setMenuLoading(false);
      return undefined;
    }
    setDatabaseStatus('checking');
    setMenuLoading(true);
    const run = async (label, request, onSuccess) => {
      try {
        const result = await request;
        if (!alive) return;
        if (result?.error) {
          console.warn(`Gagal memuat ${label}:`, result.error);
          return;
        }
        onSuccess(result);
      } catch (error) {
        if (alive) console.warn(`Gagal memuat ${label}:`, error);
      }
    };
    const tasks = [
      run('pengaturan toko', supabase.from('store_settings').select('*').eq('id', true).maybeSingle(), ({data}) => {
        if (data) setStoreSettings(current => ({...current, ...data}));
      }),
      run('kategori', supabase.from('categories').select('id,name,sort_order').eq('is_active', true).order('sort_order'), ({data}) => {
        if (data?.length) setCategories(['Semua', ...data.map(c => c.name)]);
      }),
      run('produk', supabase.from('products').select('id,name,description,price,image_url,category_id,categories(name)').eq('is_available', true).order('name'), ({data}) => {
        if (data) setProducts(data.map(p => ({id:p.id,name:p.name,description:p.description || '',price:Number(p.price),image:p.image_url,category:p.categories?.name || 'Lainnya',emoji:'🍽️'})));
      }),
      run('jadwal mingguan', supabase.from('delivery_weekdays').select('weekday,is_active').order('weekday'), ({data}) => {
        if (data) setDeliveryWeekdays(data);
      }),
      run('tanggal pengiriman berikutnya', supabase.rpc('next_delivery_date'), ({data}) => {
        if (data) setNextDeliveryDate(data);
      })
    ];
    Promise.all(tasks).finally(() => {
      if (!alive) return;
      setDatabaseStatus('connected');
      setMenuLoading(false);
    });
    return () => { alive = false; };
  }, []);
'@
if ([regex]::Matches($source,[regex]::Escape($oldAuth)).Count -ne 1) { throw 'Blok inisialisasi autentikasi tidak ditemukan tepat satu kali. App.jsx kemungkinan sudah berubah.' }
if ([regex]::Matches($source,[regex]::Escape($oldInit)).Count -ne 1) { throw 'Blok pemuatan awal tidak ditemukan tepat satu kali. App.jsx kemungkinan sudah berubah.' }
Copy-Item $path $backup
try {
  $updated = $source.Replace($oldAuth,$newAuth).Replace($oldInit,$newInit)
  [System.IO.File]::WriteAllText($path,$updated,[System.Text.UTF8Encoding]::new($false))
  $check = [System.IO.File]::ReadAllText($path)
  if (!$check.Contains('Pemeriksaan sesi membutuhkan waktu terlalu lama') -or !$check.Contains("run('produk'") -or !$check.Contains('Promise.all(tasks)')) { throw 'Validasi hasil perubahan gagal.' }
  Write-Host 'Berhasil: inisialisasi startup diperbaiki pada src/App.jsx.' -ForegroundColor Green
  Write-Host "Cadangan: $backup"
} catch {
  Copy-Item $backup $path -Force
  throw
}

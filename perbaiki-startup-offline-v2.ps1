$ErrorActionPreference = 'Stop'
$path = Join-Path (Get-Location) 'src\App.jsx'
if (!(Test-Path $path)) { throw 'src\App.jsx tidak ditemukan. Jalankan dari folder utama proyek.' }
$source = [System.IO.File]::ReadAllText($path)
$backup = "$path.bak-sebelum-fix-startup-offline-v2"
if ($source.Contains('Pemeriksaan sesi membutuhkan waktu terlalu lama') -and $source.Contains("run('produk'")) { Write-Host 'Perbaikan startup sudah terpasang.' -ForegroundColor Yellow; exit 0 }
$authPattern = '(?s)  useEffect\(\(\) => \{\r?\n    if \(!supabase\) return;.*?\r?\n  \}, \[\]\);'
$initPattern = '(?s)  useEffect\(\(\) => \{\r?\n    let alive = true;\r?\n    \(async \(\) => \{.*?\r?\n  \}, \[\]\);'
if ([regex]::Matches($source,$authPattern).Count -ne 1) { throw 'Blok autentikasi tidak cocok. App.jsx tidak diubah.' }
if ([regex]::Matches($source,$initPattern).Count -ne 1) { throw 'Blok pemuatan awal tidak cocok. App.jsx tidak diubah.' }
$newAuth = @'
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
'@
$newInit = @'
  useEffect(() => {
    let alive = true;
    if (!supabase) { setDatabaseStatus('missing-config'); setMenuLoading(false); return undefined; }
    setDatabaseStatus('checking'); setMenuLoading(true);
    const run = async (label, request, onSuccess) => {
      try {
        const result = await request;
        if (!alive) return false;
        if (result?.error) { console.warn(`Gagal memuat ${label}:`,result.error); return false; }
        onSuccess(result); return true;
      } catch (error) { if (alive) console.warn(`Gagal memuat ${label}:`,error); return false; }
    };
    const tasks = [
      run('pengaturan toko',supabase.from('store_settings').select('*').eq('id',true).maybeSingle(),({data}) => { if (data) setStoreSettings(current => ({...current,...data})); }),
      run('kategori',supabase.from('categories').select('id,name,sort_order').eq('is_active',true).order('sort_order'),({data}) => { if (data?.length) setCategories(['Semua',...data.map(c => c.name)]); }),
      run('produk',supabase.from('products').select('id,name,description,price,image_url,category_id,categories(name)').eq('is_available',true).order('name'),({data}) => { if (data) setProducts(data.map(p => ({id:p.id,name:p.name,description:p.description || '',price:Number(p.price),image:p.image_url,category:p.categories?.name || 'Lainnya',emoji:String.fromCodePoint(0x1F37D)}))); }),
      run('jadwal mingguan',supabase.from('delivery_weekdays').select('weekday,is_active').order('weekday'),({data}) => { if (data) setDeliveryWeekdays(data); }),
      run('tanggal pengiriman berikutnya',supabase.rpc('next_delivery_date'),({data}) => { if (data) setNextDeliveryDate(data); })
    ];
    Promise.all(tasks).then(results => {
      if (!alive) return;
      const successes = results.filter(Boolean).length;
      setDatabaseStatus(successes > 0 ? 'connected' : 'error');
      if (successes > 0 && successes < tasks.length) setNotice('Sebagian data online gagal dimuat. Data yang tersedia tetap dapat digunakan.');
      if (successes === tasks.length) setNotice('Terhubung ke Supabase · Katalog dan checkout menggunakan database online.');
    }).finally(() => { if (alive) setMenuLoading(false); });
    return () => { alive = false; };
  }, []);
'@
$updated = [regex]::Replace($source,$authPattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m) $newAuth},1)
$updated = [regex]::Replace($updated,$initPattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m) $newInit},1)
if ($updated -eq $source) { throw 'Tidak ada perubahan. File asli tetap aman.' }
if (Test-Path $backup) { throw "Backup sudah ada: $backup. Periksa sebelum menjalankan ulang." }
Copy-Item $path $backup
try {
 [System.IO.File]::WriteAllText($path,$updated,[System.Text.UTF8Encoding]::new($false))
 $check=[System.IO.File]::ReadAllText($path)
 if (!$check.Contains('Pemeriksaan sesi membutuhkan waktu terlalu lama') -or !$check.Contains("run('produk'") -or !$check.Contains('Promise.all(tasks)')) { throw 'Validasi hasil gagal.' }
 Write-Host 'Berhasil memperbaiki startup pada src\App.jsx.' -ForegroundColor Green
 Write-Host "Cadangan: $backup"
} catch { Copy-Item $backup $path -Force; throw }

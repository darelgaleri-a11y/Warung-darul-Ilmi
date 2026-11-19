$ErrorActionPreference = 'Stop'
$path = Join-Path (Get-Location) 'src\App.jsx'
if (!(Test-Path $path)) { throw 'src\App.jsx tidak ditemukan. Jalankan skrip dari folder utama proyek.' }
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
$old = @'
  async function saveSettings(e) {
    e.preventDefault();
    if (!settingsPassword) { setNotice('Masukkan password untuk mengonfirmasi perubahan pengaturan.'); return; }
    setSettingsBusy(true);
    const { error } = await supabase.functions.invoke('update-store-settings', {
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
    setSettingsBusy(false);
    setSettingsPassword('');
    if (!error) {
      const { data: refreshedSettings } = await supabase.from('store_settings').select('*').eq('id', true).maybeSingle();
      if (refreshedSettings) setStoreSettings(current => ({ ...current, ...refreshedSettings }));
      setBrandLogoFile(null);
      setRemoveBrandLogo(false);
    }
    setNotice(error ? `Pengaturan gagal disimpan: ${error.message}` : 'Pengaturan toko dan logo berhasil disimpan setelah verifikasi password.');
  }
'@
$new = @'
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
'@
if (!$content.Contains($old)) { throw 'Blok saveSettings berbeda dari versi yang diharapkan. File tidak diubah untuk menghindari perubahan yang salah.' }
$backup = "$path.bak-sebelum-fix-penyimpanan-pengaturan"
if (!(Test-Path $backup)) { Copy-Item $path $backup }
$content = $content.Replace($old,$new)
[System.IO.File]::WriteAllText($path,$content,(New-Object System.Text.UTF8Encoding($false)))
$check = [System.IO.File]::ReadAllText($path,[System.Text.Encoding]::UTF8)
if (!$check.Contains('functionData?.success !== true') -or !$check.Contains('finally {')) {
  Copy-Item $backup $path -Force
  throw 'Validasi gagal; file awal dipulihkan dari backup.'
}
Write-Host 'Berhasil memperbarui src\App.jsx.' -ForegroundColor Green
Write-Host "Backup: $backup"
Write-Host 'Perubahan hanya pada penanganan simpan pengaturan.'

# Analisa Ulang & Pandangan Berbeda: Boot 6.18 (Badai MIUMPU, `system_dlkm`, dan `test8-panic20s`)

Tanggal: 2026-11-23
Status: Draft analisa & rekomendasi (belum di-commit)

---

## 1. Konteks & Posisi Saat Ini

Berdasarkan catatan di `docs/PLAN-6.18-STATUS.md` serta log `log pstore uji` dan `log pstore uji`:

1. **Tiga crash awal sudah teratasi**:
   - `test1`: `mrdump` `bin_attrs` uninitialized → fixed (`968393e9db35`).
   - `test2`: KCFI panic di tracepoint UFS/MET akibat ketidakcocokan tipe `enum` vs `int` → fixed pada 97 file (`f94c481c8c5b` di `kernel_device_modules-6.18` & `d500e72bea0b` di `vendor/mediatek/kernel_modules`).
   - `test3`: `atf_logger` `ioremap_wc()` return `NULL` karena di 6.18 `of_reserved_mem` (`no-map`) tetap mengikat region ke `/proc/iomem` (`IORESOURCE_MEM`), sehingga `ioremap` ditolak oleh `region_is_ram()` → fixed dengan `memremap(..., MEMREMAP_WC)` (`326be9e98f91`).
2. **Gejala di `test4` (`log pstore uji`)**:
   - Seluruh buffer `console-ramoops-0` (256 KB) penuh dengan badai interupsi di `t = 32.466s – 32.523s` (~18.000 IRQ/detik, setiap ~54 µs) di CPU0 (`[C0]`):
     ```text
     emimpu_violation_irq: [MIUMPU]emiid0 [1c0]0;...;[3c0]104;[3c4]0;[3c8]0;[3cc]0;[3d0]7;[3d4]a;[3d8]3;[3dc]0;[3e4]2c06;[3e8]0;
     ```
   - File `log pstore uji` dan `log pstore uji` memiliki hash MD5 yang **100% identik** (`f5a681f1a8428e4f0846eb4f15319970`) dengan `log pstore uji`, yang berarti percobaan `test5`, `test6`, dan `test7` tidak menulis dump pstore baru ke ramoops.
3. **Solusi terakhir yang disiapkan sebelumnya (belum dicoba)**:
   - Mem-flash `system_dlkm.img` 6.18 yang cocok (karena di `log pstore uji` terlihat 91 modul GKI di `/system_dlkm` gagal dimuat dengan error `.gnu.linkonce.this_module section size must match the kernel's built struct module size at run time`).
   - **Bersamaan dengan itu**, mem-flash `vendor_boot-6.18-test8-panic20s.img` yang menjadwalkan `schedule_delayed_work(&emimpu_test8_work, 20 * HZ)` di `emimpu_probe()` untuk memaksa `panic()` pada `t ≈ 21.2s` (sebelum watchdog 31s).

---

## 2. Analisa Ulang & Pandangan Berbeda (Temuan Baru)

Hasil pemeriksaan silang antara register di `log pstore uji`, daftar modul di `tools/`, dan kode sumber `drivers/memory/mediatek/emi_legacy/emi_legacy_v2/` menunjukkan **4 temuan kunci**:

### Temuan 1: Badai MIUMPU `[3d8]3;[3e4]2c06` adalah **IOMMU Translation Fault** yang tidak ter-bypass karena `emi-mpu-hook-v1.ko` absen dari `tools/modules.load-6.18`

Jika kita membedah nilai register MIUMPU di `log pstore uji` terhadap `emi-mpu-v2.c` dan `emi-mpu-hook-v1.c`:
- `[3c0] = 0x104`
- `[3d0] = 0x7` (`err_case_r = 7`)
- `[3d4] = 0xa` (domain `0xa` = 10)
- **`[3d8] = 0x3` (`srinfo_r = 3`)**
- **`[3e4] = 0x2c06`, `[3e8] = 0x0` (`axi_id_r = 0x2c06`)**
  - Port EMI = `0x2c06 & 0x7 = 6` (port **MM / Multimedia**).
  - Pengecekan `axi_id_is_gpu(0x2c06)` di `emi-mpu-hook-v1.c` menghasilkan `false` (karena `(0x2c06 >> 3) & 0x7F80` adalah `0x0580 != 0x2000`).

Lihat penjelasan desain hardware di `emi-mpu-v2.c` baris 297–299:
> *"IOMMU IRQ not connected on mt6983, mt6879 and mt6895. IOMMU uses SRINFO=3 to make SMPU violation when translation fault. This behavior is security spec for IOMMU."*

Di arsitektur MediaTek MT6895:
1. Modul `emi-mpu-hook-v1.ko` (`emi-mpu-hook-v1.c`) mendaftarkan callback `by_plat_isr_hook = emi_mpu_isr_hook` ke `emi-mpu-v2.ko`.
2. Ketika terjadi violation dengan `srinfo_r == 3 && !axi_id_is_gpu(axi_id_r)` (yaitu **IOMMU translation fault** non-GPU), `emi_mpu_isr_hook()` menetapkan `bypass = true`, mencetak log dengan **`__ratelimit` (maksimal 3x per detik)**, dan mengembalikan `IRQ_HANDLED`.
3. Di `emi-mpu-v2.c` baris 215–216:
   ```c
   if (irqret == IRQ_HANDLED)
       goto clear_violation;
   ```
   Karena `irqret == IRQ_HANDLED`, ISR langsung melompat ke `clear_violation` — **tanpa** mencetak `emimpu_violation_irq: [MIUMPU]emiid0...`, **tanpa** memanggil callback Modem EE (`mpu->md_handler`), dan **tanpa** memicu `aee_kernel_exception("EMIMPU_V2", ...)`.

**Mengapa mekanisme bypass ini tidak jalan di `log pstore uji`?**
- File `emi-mpu-hook-v1.ko` **sudah dikemas di dalam ramdisk `vendor_boot`** (tercantum di `tools/recovery-modules-6.18.txt` baris 36) dan dimuat saat boot ke recovery (`tools/modules.load.recovery-6.18` baris 161).
- **NAMUN `emi-mpu-hook-v1.ko` TIDAK ADA di `tools/modules.load-6.18` (maupun `tools/modules.load`)!**
- Saat boot Android normal, stage-1 `init` hanya membaca `modules.load`. Akibatnya, `emi-mpu-v2.ko` aktif sejak `t = 1.2s` **tanpa hook (`by_plat_isr_hook == NULL`)**, sementara `emi-mpu-hook-v1.ko` baru dijadwalkan dimuat jauh belakangan dari partisi `vendor_dlkm` (`tools/dlkm/vendor_dlkm/modules.load` baris 104).
- Fakta bahwa `log pstore uji` membanjiri log dengan `emimpu_violation_irq: [MIUMPU]... [3d8]3;[3e4]2c06` membuktikan secara pasti bahwa hingga `t = 32.46s`, **`emi-mpu-hook-v1.ko` belum ter-load**.

---

### Temuan 2: Keterkaitan Gagalnya 91 Modul `system_dlkm` dengan Tidak Ter-load-nya `emi-mpu-hook-v1.ko` & Efek Samping Modem EE

1. **Rantai kegagalan DLKM**:
   - Di `log pstore uji` (baris 1900–1919), 91 modul GKI di `/system_dlkm` gagal dimuat karena ukuran `.gnu.linkonce.this_module` (`struct module`) tidak cocok dengan `boot.img` 6.18 (`6.18.32-android17-5-gecdaacc9a0ee-ab16831611-4k`), termasuk `rfkill.ko`, `zsmalloc.ko`, `pstore_zone.ko`, `netfs.ko`, dll.
   - Di `vendor_dlkm/modules.load`, `emi-mpu-hook-v1.ko` berada di **baris 104**, tepat setelah `cfg80211.ko` (baris 16), `mac80211.ko` (baris 17), `conninfra.ko` (baris 100), dan `wlan_drv_gen4m_6895.ko` (baris 102).
   - Modul `cfg80211.ko` dan stack konektivitas bergantung pada `rfkill.ko` dari `/system_dlkm`. Kegagalan memuat `/system_dlkm` menyebabkan proses pemuatan DLKM / `init` stage-2 gagal atau terhenti sebelum mencapai baris 104.
2. **Salah sasaran ke Modem Exception (`md_handler`)**:
   - Di `log pstore uji` pada `t = 4.635058`, modul `ccci_md_all.ko` sudah berhasil mendaftarkan callback Modem EE ke `emi-mpu-v2`:
     `mtk_emimpu_md_handling_register: md_handling_func registered!!`
   - Karena `emi-mpu-hook-v1.ko` belum dimuat (`by_plat_isr_hook == NULL`), begitu terjadi IOMMU translation fault (`srinfo_r = 3`), `emimpu_violation_irq` tidak melompat ke `clear_violation`, melainkan lanjut mengeksekusi `mpu->md_handler(md_str)` (`emi-mpu-v2.c` baris 290–291) yang memanggil `mdee_dumper_v5_emimpu_callback` di dalam konteks hardirq secara berulang-ulang!

---

### Temuan 3: Celah pada Pembatas Debug di Commit `f09133d503df` (`test5-dbg`)

Di commit `f09133d503df` (`emi-mpu-v2.c`), variabel `show = (emimpu_dbg_total <= EMIMPU_DBG_LIMIT)` hanya membatasi:
- `pr_err` di `emimpu_Starting_violation_debug()`
- `pr_info("%s: %s", __func__, mpu->vio_msg)`
- `schedule_work(&emimpu_work)`

Namun pada **baris 290–291** dan **baris 301–306**:
```c
if (mpu->md_handler) {
    strncpy(md_str, ...);
    mpu->md_handler(md_str);
}
```
dan `mpu->iommu_handler(...)` **tetap dipanggil tanpa pengecekan `if (show)`** pada setiap interupsi! Artinya, meskipun `printk` sudah dibatasi 16 kali, jika terjadi badai interupsi tanpa `emi-mpu-hook-v1.ko`, CPU0 tetap terjebak di dalam hardirq loop yang mengeksekusi `scnprintf` dan `mpu->md_handler` ribuan kali per detik.

---

### Temuan 4: Mengapa `test8-panic20s.img` Sebaiknya **TIDAK** Diuji Bersamaan dengan Perbaikan `system_dlkm`

1. **Jangan mencampur perbaikan nyata (`system_dlkm` 6.18) dengan bom waktu `panic(20s)`**:
   - Apabila akar masalah gagalnya boot setelah `t = 4.7s` memang berasal dari mismatch 91 modul `system_dlkm` + absennya `emi-mpu-hook-v1.ko` di `vendor_boot`, maka setelah `system_dlkm.img` 6.18 yang cocok di-flash, sistem berpeluang lanjut booting secara normal melewati detik ke-20.
   - Jika `vendor_boot-6.18-test8-panic20s.img` ikut di-flash bersamaan, maka `emimpu_test8_work` justru akan **mematikan kernel secara paksa dengan `panic()` pada detik ke-21.2**, sehingga kita tidak bisa membedakan apakah sistem sebenarnya sudah berhasil boot atau masih hang.
2. **Kelemahan `schedule_delayed_work` untuk menangkap hang kernel**:
   - `test8` menggunakan `schedule_delayed_work(&emimpu_test8_work, 20 * HZ)` yang berjalan di `system_wq` (thread/process context).
   - Jika kernel benar-benar mengalami hard lockup, CPU stall, atau kworker thread di `system_wq` tersangkut di mutex/semaphore, maka `delayed_work` tersebut tidak akan pernah dieksekusi sampai hardware watchdog (`mtk-wdt` 31s) memotong daya.
   - Jika kelak memang dibutuhkan timer diagnostik pra-watchdog, gunakan **`hrtimer`** (dieksekusi langsung di *hardirq context*) yang memanggil `show_state()` + `panic()`.

---

## 3. Rekomendasi Langkah Berurutan

### Langkah 1 — Aktifkan `emi-mpu-hook-v1.ko` Sejak Stage-1 (`vendor_boot`)
Tambahkan `emi-mpu-hook-v1.ko` tepat setelah `emi-mpu-v2.ko` di `tools/modules.load-6.18` (dan `tools/modules.load`):
- Karena `emi-mpu-hook-v1.ko` sudah ada di `tools/recovery-modules-6.18.txt` (file `.ko`-nya sudah tersedia di `/lib/modules/` dalam ramdisk `vendor_boot`), tidak perlu mengubah daftar copy modul.
- Dengan perubahan ini, `emi_mpu_isr_hook` langsung terdaftar pada `t = 1.2s` saat stage-1 init (sama seperti perilaku di TWRP), sehingga setiap IOMMU translation fault (`SRINFO=3`) langsung di-bypass dengan bersih (`IRQ_HANDLED` + ratelimit 3x/detik).

### Langkah 2 — Bersihkan `emi-mpu-v2.c` dari Bom Waktu `test8` & Lindungi `md_handler`
Di `drivers/memory/mediatek/emi_legacy/emi_legacy_v2/emi-mpu-v2.c`:
1. Hapus/batalkan perubahan `emimpu_test8_work` (`schedule_delayed_work(..., 20 * HZ)` yang memanggil `panic()`).
2. Bungkus pemanggilan `mpu->md_handler` dengan `if (show && mpu->md_handler)` sebagai pengaman lapis kedua agar callback Modem EE tidak pernah dipanggil berulang kali dalam badai IRQ.
3. Kompilasi ulang `emi-mpu-v2.ko` dan repack `vendor_boot` baru (mis. `vendor_boot-6.18-test9-emihook.img`).

### Langkah 3 — Uji Boot Murni dengan Pasangan `boot.img` + `system_dlkm.img` 6.18 yang Identik
1. Pastikan `boot.img` dan `system_dlkm.img` berasal dari artefak GKI 6.18 4KB yang sama (`6.18.32-android17-5-gecdaacc9a0ee-ab16831611-4k`).
2. Flash bersama `vendor_dlkm.img`, `odm_dlkm.img`, dan `vendor_boot` hasil Langkah 1–2 (tanpa bom waktu panic 20s).
3. Amati apakah sistem berhasil boot melewati 31 detik hingga ADB / animasi boot.

### Langkah 4 — (Hanya Jika Masih Hang Tanpa Pstore Baru) Gunakan `hrtimer` Diagnostik
Jika setelah Langkah 1–3 perangkat masih reboot di ~31 detik tanpa pstore baru:
- Pasang `hrtimer` 20 detik di `emi-mpu-v2.c` (berjalan di hardirq context, bukan `delayed_work`), yang memanggil `show_state()` (mencetak backtrace semua task yang sedang `D-state` / `R-state` ke ramoops) lalu `panic("diag 20s hrtimer")`.

---

## 4. Verifikasi dan Implementasi (2026-11-23)

- **Temuan 1 terkonfirmasi**: `emi-mpu-hook-v1.ko` ada di
  `tools/recovery-modules-6.18.txt` dan di dalam ramdisk `vendor_boot`,
  tetapi tidak ada di `tools/modules.load-6.18`. Saat boot normal,
  hook tidak didaftarkan pada stage-1.
- **Koreksi kecil**: `log pstore uji` menunjukkan `atf_logger`
  (`vendor_dlkm` baris 11) tetap dimuat pada `t = 4.66 s` setelah 91
  kegagalan `system_dlkm`. Jadi init tidak berhenti tepat setelah
  `system_dlkm`; belum terbukti apakah pemuatan `vendor_dlkm` mencapai
  baris 104. Meskipun demikian, menaruh hook di stage-1 tetap perbaikan
  yang benar dan menghilangkan ketergantungan pada urutan DLKM.
- **Langkah 1–2 sudah diimplementasikan**:
  - `tools/modules.load-6.18`: `emi-mpu-hook-v1.ko` ditambahkan tepat
    setelah `emi-mpu-v2.ko`.
  - `emi-mpu-v2.c`: bom waktu `test8` dihapus; `md_handler` dibatasi
    dengan `show`; `iommu_handler` tetap dipanggil (tidak diubah agar
    penanganan IOMMU secure tidak berubah).
  - Image: `vendor_boot-6.18-test9-emihook.img`,
    md5 `84522556a4006d2ba78f531b150e2707`,
    https://gofile.io/d/wY1Gvorv
- **Langkah 3 tetap wajib**: flash `boot.img` + `system_dlkm.img` dari
  satu paket GKI 6.18 yang sama. Jangan mencampurnya dengan panic
  buatan; test9 sengaja tanpa panic agar hasil boot murni.
- Jika test9 masih hang dan pstore tetap badai, lanjut ke Langkah 4
  (`hrtimer`), bukan `delayed_work`.

---

## 5. Analisa Ulang Pasca-`test9` (`log pstore uji`): Root Cause APU IOMMU & Solusi Tanpa Disable APU

Setelah `test9` (`vendor_boot-6.18-test9-emihook.img` + `system_dlkm.img` 6.18 yang cocok) diuji, log `log pstore uji` (identik MD5 dengan `log pstore uji`) memperlihatkan keseluruhan timeline boot dari `t = 1.35s` hingga `t = 30.72s`. Seluruh 91 error `system_dlkm` sudah hilang dan `emi-mpu-hook-v1.ko` berhasil meredam flood `printk` menjadi 3 baris/detik, namun **badai interupsi hardware ~41.150 Hz dari APU (`[MIUMPU] srinfo_r 3, axi_id_r 11270 / 0x2c06`) tetap menyandera CPU0** hingga memicu RCU stall pada `stop_machine_cpuslocked` (`t = 25.62s`) dan watchdog reset (`t ~ 31s`).

Pemeriksaan silang antara `log pstore uji`, `log pstore uji`, dan diff kernel `6.12` vs `6.18` (`common/drivers/iommu/iommu.c` & `drivers/iommu/mtk_iommu.c`) mengungkap **akar masalah (root cause) sesungguhnya** yang dapat diperbaiki secara tuntas **tanpa men-disable APU**.

### 5.1. Bukti Forensik dari `log pstore uji` dan `log pstore uji`

1. **Makna `srinfo_r = 3` dan `PA = 0x0` pada `log pstore uji`**:
   - Sesuai komentar arsitektur di `emi-mpu-v2.c:295-300`, pada MT6895 garis IRQ IOMMU tidak dihubungkan untuk translation fault; setiap **IOMMU Translation Fault** menghasilkan transaksi AXI dengan **`SRINFO = 3`** ke alamat fisik pengganti (`REG_MMU_IVRP_PADDR` / `protect_base`) agar ditangkap oleh SMPU (`emimpu_violation_irq`).
   - Pada `log pstore uji`, tepat **24 µs** setelah `apusys_rv` melepas reset uP RISC-V (`mt6895_rproc_start: smc call 11` = `MTK_APUSYS_KERNEL_OP_APUSYS_RV_START_MP` pada `t = 4.626271s`), terjadi violation pertama diikuti badai `srinfo_r = 3`:
     ```text
     [4.626271][T282] [apusys][info] mt6895_rproc_start: smc call 11
     [4.626295][C0]   [EMIMPU] emi0 comm=swapper/0:0 emi=540080f6,0,400000 axid=203c0
                      [3c0]104;[3c4]0;[3c8]0;[3cc]0;[3d0]a;[3d4]1e;[3d8]f;[3dc]0;[3e4]80f6;[3e8]0;
     [4.626330][C0]   [MIUMPU]srinfo_r 3, axi_id_r 11270
                      [3c0]104;[3c4]0;[3c8]0;[3cc]0;[3d0]a;[3d4]1e;[3d8]3;[3dc]0;[3e4]2c06;[3e8]0;
     ```
   - Perhatikan bahwa alamat fisik fault pada register MIUMPU (`[3c8]=0, [3cc]=0, [3dc]=0`) adalah **`0x0`**, yang berarti register `REG_MMU_IVRP_PADDR` (`0x114`) maupun `REG_MMU_PT_BASE_ADDR` (`0x000`) pada `APU_IOMMU0` bernilai **`0x0`**!

2. **Bukti di `log pstore uji` (`t = 1.473s`): `APU_IOMMU0` & `APU_IOMMU1` Diinisialisasi Saat Power Domain APU Masih MATI (`0x0`)**:
   - Lihat log `log pstore uji` baris 318–337 saat `mtk_iommu.ko` (di `vendor_boot`, stage-1) memanggil `mtk_iommu_attach_device()` untuk `19010000.iommu` (`APU_IOMMU0`, `(1,0)`) dan `19015000.iommu` (`APU_IOMMU1`, `(1,1)`):
     ```text
     [1.473337] mtk_iommu: mtk_iommu_hw_init done, (1,0), dump reg: 0x48:0x0, 0x50:0x0, 0x54:0x0, 0xa0:0x0, 0x110:0x0, 0x114:0x0, 0x120:0x0, 0x124:0x0
     [1.473356] mtk_iommu: mtk_iommu_attach_device, iommu_dev:19010000.iommu(1,0), user_dev:190e1000.apusys_rv, pgtable:0x12ce0001 -- 0x12ce0001 -- 0x0, tab_id:1
     ...
     [1.474776] mtk_iommu: mtk_iommu_hw_init done, (1,1), dump reg: 0x48:0x0, 0x50:0x0, 0x54:0x0, 0xa0:0x0, 0x110:0x0, 0x114:0x0, 0x120:0x0, 0x124:0x0
     [1.474796] mtk_iommu: mtk_iommu_attach_device, iommu_dev:19015000.iommu(1,1), user_dev:19024000.apusys_hw_logger, pgtable:0x12ce0001 -- 0x12ce0001 -- 0x0, tab_id:1
     ```
   - Bandingkan dengan `disp_iommu (0,0)` dan `mdp_iommu (0,1)` di baris atasnya yang membaca balik `pgtable: 0x12bf0001 -- 0x12bf0001 -- 0x12bf0001` serta register `0x48..0x124` yang semuanya **non-zero**.
   - Pada `APU_IOMMU0 (1,0)` dan `APU_IOMMU1 (1,1)`, seluruh register yang baru saja ditulis oleh `mtk_iommu_hw_init()` serta `REG_MMU_PT_BASE_ADDR` terbaca balik **`0x0`** karena power domain APU RCX masih mati!

### 5.2. Mengapa Ini Terjadi di Kernel 6.18 Tetapi Tidak di Kernel 6.12?

Perbedaan ini disebabkan oleh perubahan core IOMMU di GKI 6.18 (`common/drivers/iommu/iommu.c:448-455`, fungsi `iommu_init_device()`):

1. **Perilaku di Kernel 6.12**:
   - Saat `mtk_iommu.ko` dimuat pada stage-1 (`t = 1.47s`, dari `vendor_boot`) dan memanggil `iommu_device_register()`, `__iommu_probe_device()` hanya memproses device yang **sudah memiliki `fwspec`** (`dev_iommu_fwspec_get(dev) != NULL`).
   - Pada `t = 1.47s`, client APU (`190e1000.apusys_rv`, `19024000.apusys_hw_logger`, dll.) belum punya driver karena `apusys.ko` berada di `vendor_dlkm` (stage-2). Karena belum ada driver yang bind, `of_dma_configure()` belum pernah dijalankan pada device tersebut, sehingga `fwspec` masih `NULL` dan `mtk_iommu_attach_device()` **tidak dipanggil** pada `t = 1.47s`.
   - Nanti pada stage-2 (`t = 4.589s`), `apu_top.ko` dimuat **lebih dulu** dan menyalakan power domain APU RCX (`mt6895_apu_top_pb` -> `__apu_wake_rpc_rcx`).
   - Baru pada `t = 4.604s`, saat `apusys.ko` dimuat dan mem-probe `apusys_hw_logger` serta `apusys_rv`, kernel memanggil `platform_dma_configure()` -> `mtk_iommu_attach_device()` -> `mtk_iommu_hw_init()`. Saat itu **APU RCX sudah menyala (ON)**, sehingga inisialisasi register `APU_IOMMU0`/`APU_IOMMU1`, `REG_MMU_PT_BASE_ADDR`, dan `mtk_iommu_sec_bk_init_by_atf()` berhasil masuk ke hardware!

2. **Perilaku di Kernel 6.18**:
   - Upstream Linux 6.18 menambahkan pemanggilan `dev->bus->dma_configure(dev)` di dalam `iommu_init_device()` (`common/drivers/iommu/iommu.c:448-455`) untuk **semua** device meskipun belum memiliki driver (`!dev->driver`):
     ```c
     if (!dev->iommu->fwspec && !dev->driver && dev->bus->dma_configure) {
         mutex_unlock(&iommu_probe_device_lock);
         dev->bus->dma_configure(dev);
         mutex_lock(&iommu_probe_device_lock);
         ...
     }
     ```
   - Akibatnya, begitu `mtk_iommu.ko` memanggil `iommu_device_register()` di **stage-1 (`t = 1.473s`)**, GKI 6.18 langsung memanggil `platform_dma_configure()` dan `mtk_iommu_attach_device()` pada `190e1000.apusys_rv` dan `19024000.apusys_hw_logger` **saat `apu_top.ko` belum dimuat dan power domain APU RCX masih MATI TOTAL** (karena `MT6895_POWER_DOMAIN_APU` di `scpsys` hanyalah dummy genpd, sedangkan power RCX sesungguhnya dikendalikan oleh RPC di `apu_top.ko`).
   - Di `mtk_iommu_attach_device()` (`drivers/iommu/mtk_iommu.c:1836-1873`), blok `if (!data->m4u_dom)` dieksekusi pada `t = 1.473s` saat hardware mati:
     - `data->m4u_dom = dom;` diset (sehingga blok `if (!data->m4u_dom)` tidak pernah dijalankan lagi).
     - Semua penulisan register di `mtk_iommu_hw_init(data)`, `mtk_iommu_sec_bk_init_by_atf(APU_IOMMU, 0/1)`, dan `writel(dom->cfg.arm_v7s_cfg.ttbr, data->base + REG_MMU_PT_BASE_ADDR)` hilang karena hardware `APU_IOMMU0`/`APU_IOMMU1` belum mendapat power (`0x0`).
   - Lebih lanjut:
     - `mt6895_data_apu0` dan `mt6895_data_apu1` memiliki flag `PM_OPS_SKIP` (`mtk_iommu.c:3363-3367, 4026-4058`), sehingga ketika `apu_top.ko` menyalakan RCX pada `t = 4.590s` dan `mt6895_apu_power_on()` memanggil `pm_runtime_get_sync(apu->apu_iommu0)` & `pm_runtime_get_sync(apu->apu_iommu1)` pada `t = 4.624s`, `mtk_iommu_hw_resume()` hanya melakukan early return tanpa pernah memprogram ulang register `APU_IOMMU0`/`APU_IOMMU1` maupun `REG_MMU_PT_BASE_ADDR`!
     - Array `apu_pm_sta[0..1]` diinisialisasi ke `POWER_OFF_STA` (`mtk_iommu.c:3260`) dan tidak pernah di-update karena `mtk_iommu_update_pm_status()` tidak memiliki pemanggil di seluruh codebase, sehingga `mtk_iommu_tlb_flush_range_sync()` selalu melewati hardware TLB flush untuk `APU_IOMMU`.
     - Ketika `__apu_run()` mengalami timeout setelah 10 detik (`apu_rproc.c:91-121`), `wait_event_interruptible_timeout()` mengembalikan `ret = 0`, lalu `goto stop; return ret;` mengembalikan **`0` (dianggap sukses oleh `rproc_add`!)** tanpa memanggil `hw_ops->power_off(apu)`, sehingga APU RCX dan uP yang sedang mengalami fault storm tetap menyala selamanya.

---

### 5.3. Rencana Solusi (Tanpa Men-disable APU dan Tanpa Mengubah `common`)

Gunakan kombinasi 3 perbaikan berikut secara bersamaan:

#### Solusi 1 (Utama — di `drivers/iommu/mtk_iommu.c`): Re-init Hardware `APU_IOMMU` pada `mtk_iommu_hw_resume()` & Sinkronisasi `apu_pm_sta`
Di `kernel_device_modules-6.18/drivers/iommu/mtk_iommu.c` (`mtk_iommu_hw_resume` baris 3345–3368 dan `mtk_iommu_hw_suspend` baris 3310–3343):
1. Pada `mtk_iommu_hw_suspend()`:
   - Jika `data->plat_data->iommu_type == APU_IOMMU && data->plat_data->iommu_id < APU_IOMMU_NUM`, set `apu_pm_sta[data->plat_data->iommu_id] = POWER_OFF_STA;`.
2. Pada `mtk_iommu_hw_resume()` di dalam blok `if (MTK_IOMMU_HAS_FLAG(data->plat_data, PM_OPS_SKIP))`:
   - Jika `data->plat_data->iommu_type == APU_IOMMU`:
     - Set `apu_pm_sta[data->plat_data->iommu_id] = POWER_ON_STA;` agar operasi `mtk_iommu_tlb_flush_range_sync()` melakukan hardware TLB flush saat APU menyala.
     - Cek apakah `data->m4u_dom` sudah terpasang tetapi hardware `APU_IOMMU` belum terinisialisasi (mis. `readl_relaxed(data->base + REG_MMU_PT_BASE_ADDR) == 0` atau `readl_relaxed(data->base + REG_MMU_IVRP_PADDR) == 0` karena `mtk_iommu_attach_device` dijalankan saat RCX masih mati di stage-1).
     - Jika masih `0` (dan power RCX kini sudah menyala karena `readl_relaxed(data->base + REG_MMU_CTRL_REG)` / tulis-baca register sudah aktif), panggil `mtk_iommu_hw_init(data)` dan `writel(data->m4u_dom->cfg.arm_v7s_cfg.ttbr, data->base + REG_MMU_PT_BASE_ADDR)` sebelum `mtk_iommu_tlb_flush(data, false)`.
3. Dengan perbaikan ini, ketika `mt6895_apu_power_on()` memanggil `pm_runtime_get_sync(apu->apu_iommu0)` dan `pm_runtime_get_sync(apu->apu_iommu1)` tepat setelah `apu_top` menyalakan RCX (dan sebelum `smc call 7..11`), kedua `APU_IOMMU0` dan `APU_IOMMU1` beserta Secure Bank di TF-A (`mtk_iommu_sec_bk_init_by_atf`) akan terinisialisasi dengan benar.

#### Solusi 2 (Pendukung — di `tools/modules.load-6.18` & `tools/recovery-modules-6.18.txt`): Muat `mtk_apu_power_throttling.ko` & `apu_top.ko` di `vendor_boot` Sebelum `mtk_iommu.ko`
1. `apu_top.ko` hanya membutuhkan `mtk_apu_power_throttling.ko` serta driver core (`mtk-scpsys`, `clk-mt6895`, dll.) yang semuanya sudah dimuat lebih awal di `vendor_boot`.
2. Dengan memasukkan `mtk_apu_power_throttling.ko` dan `apu_top.ko` ke ramdisk `vendor_boot` (`tools/recovery-modules-6.18.txt` & `tools/modules.load-6.18`) **sebelum** `mtk_iommu.ko`:
   - `mt6895_apu_top_pb()` akan menyalakan power domain APU RCX (`__apu_wake_rpc_rcx`) terlebih dahulu di stage-1.
   - Saat `mtk_iommu.ko` mem-probe `19010000.iommu` dan `19015000.iommu` beberapa milidetik kemudian, hardware `APU_IOMMU0` dan `APU_IOMMU1` **sudah dalam keadaan menyala (ON)**—menyamakan kondisi hardware saat `mtk_iommu_attach_device()` dengan perilaku di kernel 6.12.
3. Menggabungkan **Solusi 1 + Solusi 2** menjamin inisialisasi `APU_IOMMU` selalu berhasil baik saat probe pertama di stage-1 maupun setelah siklus runtime suspend/resume RCX berikutnya.

#### Solusi 3 (Safety Guard — di `apusys_rv/apu_rproc.c`): Tangani Timeout `__apu_run()` dan Matikan Power APU Jika Gagal Boot
Di `kernel_device_modules-6.18/drivers/misc/mediatek/apusys/apusys_rv/apu_rproc.c` (`__apu_run`, baris 91–121):
1. Jika `wait_event_interruptible_timeout()` mengembalikan `ret == 0` (timeout 10 detik menunggu `APU_IPI_INIT`), set `ret = -ETIMEDOUT;` sebelum `goto stop;`.
2. Di blok `stop:`, selain memanggil `apu->platdata->hw_ops->stop(apu)`, panggil juga `apu->platdata->hw_ops->power_off(apu)` agar jika terjadi kegagalan inisialisasi firmware APU, power domain RCX dan `apu_iommu0/1` dimatikan dengan bersih dan tidak pernah menyandera CPU0.


---

## 6. Implementasi 2026-11-23 (pasca-`test10`)

### 6.1 Solusi 1 — diterapkan

`kernel_device_modules-6.18/drivers/iommu/mtk_iommu.c`:

- Register programming dipisah dari IRQ request:
  `mtk_iommu_hw_program()` (semua tulis register + `mtk_iommu_sec_bk_init_by_atf`)
  dipanggil oleh `mtk_iommu_hw_init()` yang tetap melakukan `devm_request_irq`.
  Pemisahan ini perlu karena `devm_request_irq` tidak idempoten, sehingga
  `mtk_iommu_hw_init()` tidak boleh dipanggil ulang saat resume.
- `mtk_iommu_hw_suspend()`: `apu_pm_sta[id] = POWER_OFF_STA` sebelum early
  return `PM_OPS_SKIP`, di bawah `data->tlb_lock`.
- `mtk_iommu_hw_resume()` untuk `APU_IOMMU`: jika `m4u_dom` sudah ada dan
  `REG_MMU_PT_BASE_ADDR` belum sama dengan `ttbr` domain (hardware mati saat
  attach stage-1), jalankan `mtk_iommu_hw_program()` lalu tulis
  `REG_MMU_PT_BASE_ADDR`. `apu_pm_sta[id]` baru di-set `POWER_ON_STA` setelah
  read-back `PT_BASE == ttbr` (bukti hardware benar-benar menyala), lalu
  `mtk_iommu_tlb_flush(data, false)`.

### 6.2 Solusi 2 — tidak diterapkan (premis tidak akurat)

Bukti dari staging 6.18:

1. `modules.dep` menunjukkan closure `apu_top.ko` = **57 modul**, dan **13**
   di antaranya belum ada di `tools/recovery-modules-6.18.txt`:
   `mtk_mdpm`, `mtk_dynamic_loading_throttling`, `mtk_pbm`,
   `ccci_util_lib`, `ccci_auxadc`, `rps_perf`, `ccmni`, `ccci_md_all`,
   `mtk_bp_thl`, `mtk_battery_oc_throttling`,
   `mtk_low_battery_throttling`, `mtk_apu_power_throttling`, `apu_top`.
   Jadi `apu_top.ko` bukan hanya bergantung pada
   `mtk_apu_power_throttling.ko`; ia menarik seluruh stack modem/CCCI/PBM
   ke `vendor_boot` stage-1.
2. `mt6895_apu_top_pb()` di `power/3.0/platform/mt6895_aputop.c` **tidak**
   memanggil `__apu_wake_rpc_rcx()`. Fungsi itu hanya dipanggil dari
   `mt6895_apu_top_on()`, yang dijalankan `apusys` saat power-on
   (`t ≈ 4.59 s`), bukan saat probe `apu_top`. Memindahkan `apu_top` ke
   stage-1 karena itu tidak menyalakan RCX sebelum `mtk_iommu` attach.

Karena Solusi 1 sudah memprogram ulang `APU_IOMMU` tepat pada
`pm_runtime_get_sync(apu_iommu0/1)` di dalam `mt6895_apu_power_on()` —
yaitu setelah `power_dev` (RCX) menyala dan sebelum SMC start uP — urutan
modul tidak lagi menjadi syarat kebenaran. Solusi 2 dibatalkan agar stack
modem tidak ikut dimuat di stage-1.

### 6.3 Solusi 3 — diterapkan

`kernel_device_modules-6.18/drivers/misc/mediatek/apusys/apusys_rv/apu_rproc.c`:

- Timeout `wait_event_interruptible_timeout()` sekarang mengembalikan
  `-ETIMEDOUT` (sebelumnya `0`/sukses).
- Blok `stop:` memanggil `hw_ops->power_off()` setelah `hw_ops->stop()`,
  hanya bila `F_FAST_ON_OFF` tidak diset (platform itu tidak memanggil
  `power_on()` di jalur ini).
- Kegagalan `power_off` hanya dicatat, tidak menimpa `ret` awal.

### 6.4 Verifikasi build

- `bazel build //kernel_device_modules-6.18/drivers/iommu:mtk_iommu.mgk_64_k618.6.18.user`
  dan `.../apusys:apusys.mgk_64_k618.6.18.user`: sukses.
- `KVER=6.18 build.sh user` (target
  `mgk_64_k618_customer_modules_install.user`): sukses.

### 6.5 Artefak uji

| Image | Ukuran | MD5 |
|---|---:|---|
| `vendor_boot-6.18-test11-iommu.img` | 67.108.864 B | `0ee453c16ae20b6dfbf2cc4bf0db492e` |
| `vendor_dlkm.img` | 24.551.424 B | `70144e66a846b1de359d99c82afbd264` |
| `odm_dlkm.img` | 4.206.592 B | `da2c64a1572ff27382128beb4bbcba8b` |

Unduhan: https://gofile.io/d/oTgnm1xd

Pasangkan dengan `boot.img` + `system_dlkm.img` GKI
`6.18.32-android17-5-gecdaacc9a0ee-4k` yang sama. Verifier 8 gerbang:
8/8 PASS (487 modul; 0 unresolved/CRC mismatch).

## 7. Regresi audio 6.18 — flag DPCM pada `mt6895-mt6368` (2026-11-23)

**Status:** akar kegagalan registrasi kartu teridentifikasi dari log dan
perbandingan sumber dengan baseline 6.12 KMI 6. Perbaikan sudah diterapkan,
build + repack + verifier 8/8 lulus, dan audio terkonfirmasi aman di
perangkat (`log kernel uji`). Lihat [rencana port 6.18](PLAN-6.18.md).

### 7.1 Bukti dari `log kernel uji`

```text
[    5.684120] Hostless_LPBK: ASoC error (-22): substream Hostless_LPBK has no playback, no capture
[    5.684128] mt6895-mt6368 sound: ASoC: can't create pcm Hostless_LPBK :-22
[    5.687676] mt6895-mt6368 sound: mt6895_mt6368_dev_probe snd_soc_register_card fail -22
```

Kedua amplifier FS1599 (`6-0034` dan `6-0035`) sudah berhasil probe
sebelumnya. Kegagalan yang menghentikan registrasi kartu adalah `-EINVAL`
ketika ASoC membuat PCM `Hostless_LPBK`. Pesan `adsp_system_bootup fail
ret(-14)` juga muncul pada 6.12 karena node `adspsys@1e000000` dinonaktifkan
di DT X6871 (lihat [PRETEST.md §52.1](PRETEST.md#521-audio-tran_audio_controlko--mt6895-mt6368ko-vendor_dlkm));
pesan tersebut bukan penyebab kegagalan registrasi ini.

### 7.2 Perbedaan dengan 6.12 KMI 6

Commit port `a20a68e37647` mengganti `.dpcm_playback` dan `.dpcm_capture`
dengan `.playback_only` dan `.capture_only` satu per satu di
`sound/soc/mediatek/mt6895/mt6895-mt6368.c`. Pada 6.12, kedua flag DPCM
bernilai `1` membiarkan link dua arah tetap mendukung playback dan capture.
Pada 6.18, `soc_get_playback_capture()` di `common/sound/soc/soc-pcm.c`
memakai `.playback_only` untuk menonaktifkan capture dan `.capture_only`
untuk menonaktifkan playback. Jika keduanya bernilai `1`, kedua arah
dinonaktifkan dan fungsi mengembalikan `-EINVAL`.

`Hostless LPBK DAI` sendiri mendeklarasikan kedua arah. Ada **17 link**
dengan kedua flag `*_only` aktif di `mt6895-mt6368.c`, mencakup front-end
dan back-end. Membetulkan `Hostless_LPBK` saja tidak cukup.

### 7.3 Usulan perbaikan dan verifikasi

1. Di driver perangkat 6.18, hilangkan kedua flag `*_only` dari link yang
   memang dua arah. Pertahankan hanya flag yang sesuai pada link satu arah.
   Cocokkan setiap link dengan kemampuan DAI dan arah pada baseline 6.12;
   pertahankan nama, urutan link, dan routing mixer untuk ABI HAL X6871.
2. Build dan repack `vendor_dlkm` dari staging 6.18 terbaru. Modul yang
   ditargetkan adalah `mt6895-mt6368.ko`; GKI `common`, DTB, dan baseline
   6.12 tidak perlu diubah. Ikuti [status port](PLAN-6.18-STATUS.md#perintah-kerja)
   dan [prosedur repack](BOOTTEST.md#2-membuat-image-vendor_boot--dlkm).
   Jalankan `tools/verify-kmi-abi.py --kver 6.18` dan pastikan 8/8 lulus.
3. Pada perangkat, pastikan kartu muncul di `/proc/asound/cards` dan tidak
   ada lagi `no playback, no capture`. Uji speaker FS1599, earpiece, dan
   perekaman mikrofon; lulus verifier saja tidak membuktikan audio bekerja.

### 7.4 Implementasi dan verifikasi (2026-11-23)

- `kernel_device_modules-6.18/sound/soc/mediatek/mt6895/mt6895-mt6368.c`:
  menghapus pasangan `.playback_only = 1` + `.capture_only = 1` dari
  **17 link dua arah** (count playback 34 → 17, capture 37 → 20; selisih
  tepat 17/17). Flag pada link satu arah tidak diubah.
- Build: `bazel build
  //kernel_device_modules-6.18/sound/soc/mediatek/mt6895:mt6895-mt6368.mgk_64_k618.6.18.user`
  sukses (28,9 s, cache `out_bazel_test`).
- Repack: `tools/repack-dlkm-latest.sh` sukses; 209 `.ko` vendor_dlkm,
  57 `.ko` odm_dlkm, AVB hashtree terverifikasi.
- `tools/verify-kmi-abi.py --kver 6.18`: **8/8 PASS**, 487 modul,
  0 unresolved/CRC mismatch, 0 non-KMI import.
- Artefak: `vendor_dlkm-6.18-audio-dpcm.img`, 24.551.424 B,
  md5 `ad24e0ac5d51c070fe3db2e41f4e18e8`,
  https://gofile.io/d/oTgnm1xd
- **Terkonfirmasi di perangkat:** audio aman pada `log kernel uji`. Amplifier
  speaker FS1599 menunjukkan siklus `spk_amp_event 2/4` berulang saat
  playback (t=40.29/42.20, 47.46/49.99, 70.17/71.35, 91.75 s), bukan lagi
  kegagalan registrasi kartu. Error `snd-audio-dsp` PCM open tetap ada
  karena ADSP tidak aktif, tetapi tidak menghambat audio yang diuji.

## 8. Facebook Story 6.18 — uji perbaikan di sisi kernel

- `log kernel uji`: tiga sesi VP9 non-secure (`svp 0`, konteks 31/33/35) berhasil
  membuat instance MediaTek, lalu `vdec_vcp_decode()` melaporkan
  `unsupported (-1,-1)` dalam 1–3 ms. `QBUF` gagal setelah penolakan itu.
  Tidak ada fault IOMMU VDEC pada percobaan ini. `log kernel uji` sebelumnya
  merekam fault tersendiri: H.264 berhasil init pada 720×1280 dan
  368×640, lalu `LAT_WDMA` dan `CORE/VLD` sama-sama fault di `0x31c00000`.
- `log Android` hanya mencakup buffer `events` saat boot, bukan sesi
  playback. Log itu tidak mengidentifikasi profil VP9 atau fallback
  yang dipilih Facebook.
- [Dump stock X6871 SP20](https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871/-/blob/X6871-16.3.0.155SP20%28OP008PF001AZ%29/all_files.txt)
  dipakai sebagai referensi. Pengguna mengonfirmasi bahwa modul stock
  dapat memutar Story. Decoder VP9 hardware tetap aktif; usulan fallback
  lewat XML tidak dipakai.

### 8.1 Perubahan build uji

- `mtk_iommu.ko` (`vendor_boot`): saat invalidasi HypMMU Type-2 untuk
  IOMMU multimedia MT6895, gunakan ID tabel hardware (`MM_TABLE=0`),
  bukan tag firmware milik klien pertama yang menempel ke domain.
  Di `log kernel uji`, `iommu_test` membuat domain VDEC sebelum klien UBE;
  domain itu mewarisi tag `1`. Pada fault H.264, lookup software masih
  menemukan PA, tetapi lookup hypervisor di tabel multimedia memberi `0`.
  Ini kandidat perbaikan H.264, belum bukti penyebab penolakan VP9.
  Jalur APU, pengelompokan domain, dan proteksi IOMMU tidak diubah.
- `mtk-vcodec-dec.ko` (`vendor_dlkm`): tambah pesan `VP9 header rejected`
  dengan ukuran payload, panjang buffer, offset, flag, dan bit status.
  Hanya dicetak jika VCP menolak header VP9 non-secure; bukan perubahan
  perilaku decode. Tidak ada salinan payload video yang dicetak.

### 8.2 Artefak dan uji perangkat

Hasil build/repack ada di `<artefak-lokal>/vdec-kernel-test/`.
Verifier KMI/ABI **8/8 PASS** untuk 487 modul, dan hashtree DLKM lulus.
`common`, DTB, bootconfig, fragmen recovery, policy TWRP, dan konfigurasi
codec Android tidak diubah. `odm_dlkm.img` hasil repack identik dengan
image sebelumnya.

| Image uji | MD5 |
|---|---|
| `vendor_boot-6.18-vdec-test.img` | `04e34410592666fc0050264a205af9bb` |
| `vendor_dlkm.img` | `4f8dc3fe049200af443f122030cf1c78` |

Unduhan: https://gofile.io/d/2DHz5NGR (kedua image di folder
`6.18-vdec-test`; MD5 di atas sudah dicocokkan dengan file yang diunggah).

Uji kedua image bersama pasangan `boot`/`system_dlkm` GKI 6.18 yang sama.
Pada Story yang gagal sebelumnya, cek apakah fault `LAT_WDMA`/`CORE/VLD`
hilang dan apakah VP9 masih ditolak. Jika VP9 masih gagal, ambil baris baru
`VP9 header rejected`; gunakan TikTok sebagai kontrol.

### 8.3 Hasil `log kernel uji` dan kandidat perbaikan sinkronisasi DMA VP9

**Build §8.2 tidak memperbaiki Story.** `log Android` mencatat pembukaan
`StoryViewerActivity` pada 00:11:26.855, disusul penolakan VP9 pertama
sekitar 00:11:27.083 setelah mencocokkan waktu kedua log. Sembilan sesi
ditolak dengan `changed=0x4` setelah inisialisasi VCP sukses. Buffer input
berisi data (17.927–644.324 B dari 2.094.080 B, offset 0). Tidak ada fault
VDEC H.264 pada percobaan ini, tetapi juga tidak ada `Init Vdec OK` untuk
H.264; hasil tersebut belum memvalidasi perubahan IOMMU.

Kandidat berikutnya di `mtk-vcodec-dec.ko`: sinkronkan scatterlist DMA-BUF
asli memakai perangkat dan arah DMA dari attachment tepat sebelum VCP
membaca header VP9, bukan hanya mengandalkan sinkronisasi parsial saat
`buf_prepare`. Tambahkan `dma_wmb()` agar descriptor input dipublikasikan
sebelum `DEC_START`. Sinkronisasi tambahan hanya untuk header awal VP9
non-secure dengan payload dan tetap menghormati `NO_CACHE_CLEAN`.
Penolakan firmware tidak diabaikan dan jalur codec lain tidak diubah.
Ini menguji kemungkinan data input belum terlihat oleh VCP, bukan akar
masalah yang sudah terbukti.

- Artefak lokal: `<artefak-lokal>/vp9-dma-test/vendor_dlkm-6.18-vp9-dma-test.img`.
- Unduhan: https://gofile.io/d/fZX9rpS6
- MD5: `e6fa2cd59b3267f0f0c79595b780c33a`; SHA-256:
  `fc53afcc2068df3585b233f986dabc86ec44a979f1537ea0fcca64288df120d7`.
- Build, AVB hashtree, dan verifier KMI/ABI 8/8 lulus. Dibandingkan build
  §8.2, hanya `mtk-vcodec-dec.ko` yang berubah; `odm_dlkm` identik.
- Cukup ganti `vendor_dlkm` apabila sudah memakai set §8.2 untuk
  `log kernel uji`; pertahankan `vendor_boot`, `odm_dlkm`, GKI dan konfigurasi
  vendor yang sama.
- **Hasil uji perangkat: Story tetap hitam.** Cuplikan ulang menunjukkan
  VP9 masih ditolak dengan `changed=0x4`, offset `0`, dan buffer berisi
  payload. Dua sesi H.264 (`480×864` dan `720×1280`) melewati tahap
  `Init Vdec OK`; cuplikan yang dibagikan tidak memuat `TF larb` atau
  `queue_error_code_event`, tetapi belum membuktikan frame H.264 tampil.
  Sinkronisasi tambahan tidak menyelesaikan penolakan VP9.

Untuk membedakan input yang diterima kernel dari respons VCP tanpa flash
ulang, aktifkan sementara `mtk_v4l2_dbg_level=3` pada modul
`mtk_vcodec_dec`. Level ini mencetak metadata buffer, sembilan byte awal
input, dan ID/status IPI; kembalikan nilainya setelah percobaan.

**Hasil debug:** dua input yang ditolak memiliki header keyframe VP9
Profile 0 dengan sync code `49 83 42`. Dimensi yang terbaca dari header
adalah `540×960` (konteks 83) dan `720×1280` (konteks 85). Ini menunjukkan
awal bitstream masuk akal saat dibaca CPU, tetapi tidak membuktikan VCP
membaca byte yang sama atau seluruh frame valid. VCP mengirim
`B001` (`DEC_START_DONE`) dengan status `-1`; bukan timeout. Konteks 85
menggunakan IOVA input `0x12fe00000`, di dalam aperture Video uP VDEC
`0x110000000..0x12fffffff`. Alamat di atas 4 GiB memang sesuai desain
aperture; log ini tidak menunjukkan truncation. `C005`/`C006` adalah
permintaan alokasi/bebas dari VCP; status pada baris `pop msg_id` bukan
hasil alokasi di AP.

**Hasil log alokasi berikutnya:** konteks 105/107/108/110 masing-masing
mendapat tiga buffer `MEM_TYPE_FOR_SW` (tipe 0; 37.096, 1.832, 14.440 B)
dan tiga buffer `MEM_TYPE_FOR_HW_CACHE` (tipe 2; 263.168, 62.464,
123.904 B). Semua IOVA nonzero dan tidak ada kegagalan alokasi/mapping
yang dilaporkan AP pada cuplikan ini. VCP tetap menolak `DEC_START`
setelah buffer itu disiapkan. Kolom `pa` di log ini bukan alamat fisik:
`mtk_vcodec_alloc_mem()` mengisinya dengan alamat DMA yang sama dengan
`iova`. Keberhasilan map di AP tidak membuktikan VCP dapat membaca
mapping atau isinya.

Pemeriksaan berikutnya: bandingkan satu sampel VP9 yang sama pada stock
SP20 dan port 6.18, termasuk hasil `DEC_START_DONE`, perangkat DMA dan
rentang IOVA untuk bitstream serta buffer kerja. Tidak perlu mengulang
capture alokasi yang sama. Belum ada bukti untuk memaksa IOVA 32-bit,
mengganti heap, atau mengubah IOMMU lagi.

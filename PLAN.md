# PLAN — Port driver ke sumber X6871 (Infinix GT 20 Pro)

Dokumen ini rencana kerja. `README.md` = cara build yang sudah jalan,
`HANDOFF.md` = status build + jebakan. Dokumen ini = apa yang belum jalan.

Status per 2026-11-18. Semua angka di bawah hasil pengukuran, bukan perkiraan.

---

## 1. Masalah

Mau bikin source kernel untuk device yang source-nya tidak dipublikasikan
vendor. Target: **Infinix X6871 (GT 20 Pro)**, `X6871-16.3.0.155SP20`.

Titik keberangkatan yang menguntungkan:

```
X6871  : MT6895 (Dimensity 8200 Ultimate), kernel 6.12.38-android16-5-gb575a0b6e647
W1VO   : mt6895                          , kernel 6.12.38-android16-5-g2c4fd33ae6d8
                                                       ^^^^^^^^ KMI generation sama
```

Soc sama, versi kernel sama, generasi KMI sama. Jadi **tree w1vo yang sudah bisa
build dipakai sebagai basis**, bukan diganti. X6871 cuma jadi donor.

---

## 2. Selisih modul (terukur)

Bandingkan 546 modul di firmware X6871 vs 764 modul hasil build w1vo:

| | jumlah |
|---|---|
| modul firmware X6871 | 546 |
| sudah dibangun w1vo (baseline) | **439** (80%) |
| sudah dibangun w1vo (setelah Tingkat A) | **452** (82%) |
| selisih awal | 107 |
| **selisih sekarang** | **94** |

107 selisih itu dipecah 4 tingkat:

| Tingkat | Isi | Jumlah | Status |
|---|---|---|---|
| **A** | sudah ada target Bazel di tree w1vo, cuma dimatikan config | **13** | ✅ selesai |
| **B** | sudah dibangun tapi beda nama (`fpsgo`→`mtk_fpsgo_v3/v8`, `game`→`mtk_game`) | **2** | belum |
| **C** | source Transsion/MTK ada di donor (6.1 atau OPPO 6.12) | **38** | ⚠️ blokir struktural, lihat §5 |
| **D** | tidak ada di mana pun | **~41** | belum |

Catatan penting hasil investigasi: dari 94 selisih, **hanya 15 yang dirujuk
device tree X6871**. Sisanya kemungkinan dependensi internal atau modul yang
tidak dipakai build ini. Lihat §5.0c.

---

## 3. Tingkat A — 12 modul, cuma perlu flag  ✅ SELESAI

Bukan port. Ini modul MTK "legacy" yang **sudah ada di tree w1vo** dan sudah
punya target Bazel. Kita mematikannya sendiri waktu build dengan
`DEFCONFIG_OVERLAYS=` kosong.

File yang mengatur: `kernel_device_modules-6.12/kernel/configs/entry_level_legacy.config`

```
CONFIG_MTK_CM_MGR_LEGACY_V1=m          -> mtk_cm_mgr_legacy_v1
CONFIG_MTK_CM_MGR_MT6895=m             -> mtk_cm_mgr_mt6895
CONFIG_MTK_LPM_LEGACY=m                -> mtk-lpm-legacy
CONFIG_MTK_LPM_MT6895=m                -> mtk-lpm-plat-v1-legacy, mtk-lpm-dbg-mt6895-legacy
CONFIG_MTK_LPM_GS_DUMP_SUPPORT=y
CONFIG_MTK_SWPM_MODULE_LEGACY_V2=m     -> mtk-swpm-legacy
CONFIG_MTK_SWPM_MT6895=m
CONFIG_MTK_SWPM_PERF_ARMV8_PMU_LEGACY_V2=m -> mtk-swpm-perf-arm-pmu-legacy
CONFIG_MTK_EMI_LEGACY=m                -> emi-mpu-v2
```

### Hasil build (terverifikasi 2026-11-18)

```
flag    : --repo_env=DEFCONFIG_OVERLAYS=entry_level_legacy.config
hasil   : Build completed successfully, 784 actions, 715s
modul   : 764 -> 775  (+13, -2)
gap     : 107 -> 94   (coverage 439/546 = 80% -> 452/546 = 82%)
```

13 modul yang hidup (semua menutup selisih nyata, 0 bonus):

```
emi-mpu-hook-v1   emi-mpu-v2          mtk-lpm-dbg-common-v1-legacy
mtk-lpm-dbg-mt6895-legacy             mtk-lpm-legacy
mtk-lpm-plat-v1-legacy                mtk-swpm-dbg-common-v1-legacy
mtk-swpm-dbg-v6895                    mtk-swpm-legacy
mtk-swpm-perf-arm-pmu-legacy
mtk_cm_ipi_legacy_v1                  mtk_cm_mgr_legacy_v1
mtk_cm_mgr_mt6895
```

Catatan: PLAN awal menebak 12, hasilnya 13. Bedanya `mtk-swpm-dbg-v6895` —
ikut hidup dari blok yang sama, tidak saya hitung karena di daftar gap
namanya `mtk-swpm-dbg-v6895` dan saya salah memasukkan yang `...-legacy`.

2 modul yang hilang, dan aman:

```
ffa-core, ffa-module   -> X6871 tidak memakai keduanya (0 di firmware)
ffa_v11                -> tetap ter-build; modinfo depends kosong
```

Semua `.ko` baru ber-vermagic benar
(`6.12.38-android16-5-g2c4fd33ae6d8-4k SMP`).

---

## 4. Tingkat B — 2 modul, rename

`fpsgo` dan `game` sudah dibangun sebagai `mtk_fpsgo_v3`, `mtk_fpsgo_v8`,
`mtk_game`. Firmware menamai `.ko`-nya beda. Tidak ada pekerjaan source.
Perlu dicek apakah ada yang meng-`request_module("fpsgo")` — kalau iya,
sediakan symlink/alias di `.ko` atau di userspace.

---

## 5. Tingkat C — 38 modul, port dari donor mt6897  ⚠️ BLOKIR STRUKTURAL

### 5.0 Hasil investigasi — baca ini dulu

Waktu mulai mengeksekusi Tingkat C, ketemu dua hal yang mengubah rencana.
Keduanya terukur, bukan dugaan.

**(a) `tc_charger_class` bukan penambahan, tapi PENGGANTI.**

Transsion mem-fork `charger_class.c` MTK. Perbandingan simbol:

```
simbol diekspor charger_class.c MTK       : 104 dipakai driver lain
simbol diekspor tc_charger_class.c        : 115
simbol bentrok (nama sama, definisi beda) : 78
```

Artinya `tc_charger_class` **tidak bisa hidup berdampingan** dengan
`charger_class` MTK. Di device X6871 tidak ada `charger_class.ko` sama sekali —
hanya `tc_charger_class.ko`. Jadi ini migrasi framework, bukan tambah modul.

**(b) X6871 membuang seluruh framework charger MTK.**

Modul MTK yang kita bangun tapi **tidak ada** di firmware X6871:

```
charger_class   adapter_class   mtk_charger_framework
mtk_charger_algorithm_class     mtk_pd_adapter   mtk_pd_charging
mtk_chg_type_det  mtk_pep  mtk_pep20  mtk_pep40  mtk_pep45  mtk_pep50
mtk_hvbpc  mtk_ufcs_adapter  mtk_2p_charger
```

15 modul. Kalau Transsion dipasang, 15 modul ini harus **dilepas**, dan
`mt6375-charger`, `mt6375-battery`, `mtk_battery_manager` dll harus tetap
jalan di atas API Transsion.

Kabar baiknya: sudah diuji. `mt6375-charger.ko` di device mengimpor 6 simbol
`charger_dev_*`, dan **keenamnya disediakan** `tc_charger_class.ko`. Jadi
kompatibel — tapi ini pekerjaan ganti-fondasi, bukan salin-file.

**(c) DT menunjukkan yang benar-benar dipakai cuma 15 dari 94 modul.**

Dari 94 selisih, yang disebut di DT X6871 hanya 15:

```
aw8601af   ocp81375_v4l2   sgm37864_v4l2   pca_tfcp_ta
rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871
tc_auto_test  tc_gauge  tc_pd_adapter  tc_pmic  tc_tcpc
tc_trancare   tran_audio_control  tran_fp  tran_ldo  tran-led-core
```

Sisanya (79 modul) tidak dirujuk DT — kemungkinan besar dependensi internal
atau modul yang memang tidak dipakai build ini.

### 5.1 Ketersediaan source untuk 15 modul yang DT butuhkan

| Modul | Source ada di | Catatan |
|---|---|---|
| `tc_auto_test` `tc_gauge` `tc_pd_adapter` `tc_pmic` `tc_tcpc` | donor 6.1 | butuh fondasi Transsion (5.0a) |
| `tran_audio_control` | donor 6.1 | mandiri, 628 baris |
| `ocp81375_v4l2` `sgm37864_v4l2` | donor 6.1 | port flashlight |
| `tran_fp` | donor 6.1 | CMD, perlu TEE |
| `aw8601af` `pca_tfcp_ta` `tran_ldo` `tran-led-core` `rm69220...` | **tidak ada** | Phase 3 / cari donor |

### 5.2 Yang bisa dikerjakan tanpa ganti fondasi — hasil

Langkah 1 dikerjakan 2026-11-19. Dari 4 kandidat, **3 berhasil, 1 ditolak**.

| Modul | Baris | Hasil | Catatan |
|---|---|---|---|
| `tran_audio_control` | 716 | ✅ **ter-build** | 1 patch: `.remove` → `void` |
| `splitswitch-gpio` | 353 | ✅ **ter-build** | 1 patch: `.remove` → `void`; 4 include dibuang |
| `hiber` | 967 | ✅ **ter-build** | 3 patch: `strlcpy`→`strscpy`, 2 signature tracepoint binder |
| `leds-aw22xxx` | 1818 | ❌ **ditolak** | butuh framework `tc_led_class` (lihat bawah) |

**Kenapa `leds-aw22xxx` ditolak:** `leds-aw22xxx.c` meng-include
`tc_led_class.h` dan memakai `tc_led_device_register()`, `tc_led_ops`,
`tc_led_class`. Itu bagian dari framework LED Transsion
(`drivers/power/supply/transsion/leds/tc_led.c`), bukan modul mandiri.
Menambahkannya berarti menyeret fondasi charging/LED Transsion — persis yang
kita tunda di §5.0. File sudah dikembalikan, tidak ditinggal di tree.

**Patch yang ternyata diperlukan (6.1 → 6.12):**

| Pola | Jumlah | Contoh |
|---|---|---|
| `platform_driver.remove` kembali `void` (bukan `int`) | 2 | `splitswitch-gpio.c`, `tran_audio_control.c` |
| `strlcpy` dihapus → `strscpy` | 1 | `tran_hiber.c` |
| signature tracepoint vendor hook berubah | 2 | `android_vh_binder_preset` (+`binder_proc *`), `android_vh_binder_alloc_new_buf_locked` (+`bool *should_fail`) |

Catatan `hiber`: ia mengait ke **binder internal** lewat vendor hook. Butuh
`CONFIG_ANDROID_VENDOR_HOOKS=y` — sudah aktif di build kita, jadi aman.

**Pelajaran untuk modul berikutnya:** sebelum port, cek apakah file
meng-include header `tc_*` atau memakai `tc_*_register()`. Kalau iya, modul itu
**bukan** mandiri — tolak dan tunda sampai fondasi Transsion dipasang.


Stack audio Transsion (`aw87xxx`, `fs1599`, `oca72xxx`, `elliptic`) sekitar
70.000 baris, mandiri, tapi butuh `BUILD.bazel` DDK baru untuk tiap codec.

### 5.3 Jebakan nyata: aw36515 (sudah dicoba)

Percobaan pertama: salin `aw36515.c` dari donor 6.1. **Gagal compile** dengan
2 error:

```
aw36515.c:744: error: use of undeclared identifier 'FLASH_IOC_SET_CURRENT'
aw36515.c:1094: error: incompatible function pointer types initializing
                'int (*)(struct i2c_client *)' with 'int (struct i2c_client *,
                const struct i2c_device_id *)'
```

Sebabnya: header 6.12 (`flashlight.h`) menghapus `FLASH_IOC_SET_CURRENT`, dan
`i2c_driver.probe` di 6.12 tidak lagi menerima argumen `i2c_device_id`.

**Jalan keluarnya bukan patch, tapi pakai source yang sudah 6.12.** Donor OPPO
kita (`donor/oppo-mt6896`, tree 6.12) punya `aw36515_23021.c` yang sudah
6.12-native: `probe(struct i2c_client *client)`, tanpa `FLASH_IOC_SET_CURRENT`,
lengkap dengan `BUILD.bazel` yang sudah jalan.

Pelajaran untuk sisa Tingkat C: **cek donor OPPO 6.12 dulu sebelum port dari
6.1.** Untuk nama modul yang sama persis, OPPO 6.12 hanya punya 1 (`game`),
tapi untuk codec audio/flashlight filenya beda nama dan sudah native.

### 5.4 Rekomendasi urutan Tingkat C

1. `tran_audio_control` + `splitswitch-gpio` — bersih, ~1.000 baris, mandiri.
2. `leds-aw22xxx`, `hiber` — mandiri, ~2.800 baris.
3. `aw8601af` / `ocp81375` / `sgm37864` — pakai pola 5.3 (cari yang 6.12-natively
   di donor OPPO dulu).
4. Stack audio penuh (~70k baris) — butuh penulisan `BUILD.bazel` per codec.
5. **Charging Transsion (5 modul DT + fondasi)** — kerjakan paling akhir,
   karena ini ganti fondasi dan harus melepas 15 modul MTK (§5.0b).


---

## 6. Tingkat D — ~55 modul, belum ada source

Kebanyakan utility Transsion (`tran_zram`, `tran_ldo`, `tran_rhi`,
`tran-led-core`, `tran_scsi_mod`, `tran-ufshcd-*`, `trans_sched`,
`priority_allocate`, `low_latency_sched`, dsb).

**Jangan langsung RE.** Yang lebih murah: cari drop Transsion lain di generasi
kernel yang sama. Repo OPPO/OnePlus sudah kebukti menyimpan banyak dari ini
(lihat §7). Satu donor 6.12 yang cocok bisa menghapus hampir seluruh tingkat ini.

---

## 7. Phase 3 — panel + Iris (INI YANG PALING PENTING)

Panel adalah satu-satunya penghalang boot sungguhan. Tiga modul:

```
rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871   <- panel utama X6871
rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_cl8
ili7838e_fhdp_dsi_cmd_dsc_tm_tm_120hz_cl9
```

### 7.1 Framework panel 6.1 == 6.12 (terverifikasi)

```
mtk_drm_panel_drv.h          102 vs 102   IDENTIK
mtk_drm_panel_common.h        59 vs  59    IDENTIK
mtk_drm_panel_helper.h       603 vs 603   IDENTIK
mtk_drm_panel_helper_dsi.c  2889 vs 2889  IDENTIK
mtk_drm_panel_drv.c           97 vs  97    IDENTIK
```

Byte-identik. Artinya driver panel 6.1 bisa drop-in; API-nya tidak berubah.
Drift hanya di `mtk_panel_ext.h` (762 → 884 baris, murni aditif), dan
struct-nya cuma kehilangan:

| Hilang di 6.12 | Dipakai rm692j0? |
|---|---|
| `vdo_per_frame_lp_enable` | tidak (0) |
| `hbm_set_cmdq_switch` | ya (2) |
| `lcm_power_set` | ya (2) |

Jadi paling banyak 3 penghapusan per driver panel.

### 7.2 Iris — WAJIB, bukan opsional

Panel X6871 punya `pxlw-iris-enable = <1>` di DT, dan `.ko`-nya mengimpor
9 simbol `iris_*` sebagai UND. Semua 9 diekspor `mediatek_drm_v1.ko` di device:

```
iris_enable  iris_disable  iris_reset  iris_reset_off  iris_set_valid
iris_is_pt_mode  iris_panel_cmd_passthrough  iris_conver_one_panel_cmd
iris_loop_back_validate
```

Dan firmware Iris-nya ada di dump:

```
vendor/firmware/iris5.fw
vendor/firmware/iris5_ccf1.fw
vendor/firmware/iris5_ccf2.fw
vendor/firmware/pxlw-rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.fw   <- per-panel
```

Ada fw per-panel yang namanya persis sama dengan panel = Iris memang dipakai
di jalur display panel ini.

**Tree w1vo tidak punya satu baris pun `iris_`.** Donor mt6897 juga tidak.

### 7.3 Sumber Iris yang cocok (sudah ditemukan)

`oppo-source/android_kernel_oppo_mt6896` (yang ditunjuk user) **bukan**
tempatnya — itu kernel mainline, `mediatek_v2` tidak ada di sana. Sibling-nya
`android_kernel_modules_oppo_mt6896` punya `mediatek_v2` tapi hanya
`color_softiris_status` (software color tuning, bukan hardware Iris).

Yang benar (hasil GitHub code search):

| Repo | Lokasi iris | SoC | Pakai |
|---|---|---|---|
| `OnePlusOSS/android_kernel_5.10_oneplus_mt6895` | `mediatek_v2/iris_*.c` | **mt6895** | **YA — ini yang dipakai** |
| `oppo-source/android_kernel_modules_and_devicetree_oppo_mt6897` | `vendor/oplus/.../drm/iris/` | mt6897 | alternatif |
| `Oneplus-Ce5/android_kernel_modules_oneplus_mt6897` | `oplus/.../iris/core/` | mt6897 | alternatif |

Branch yang dipakai: `oneplus/mt6895_v_15.0.0_ace` (paling baru, Android 15).

File (16 `.c`, ~8.950 baris, sudah diunduh ke `tmp/iris-src/`):

```
iris_cmds.c   iris_i2c.c    iris_i3c.c     iris_loop_back.c
iris_extended.c  iris_gpio.c  iris_ioctl.c   iris_frc.c
iris_pq.c     iris_lp.c     iris_lightup.c  iris_lightup_ocp.c
iris_lut.c    iris_mode_switch.c  iris_timing_switch.c  iris_dbg.c
```

Header: `iris_api.h iris_def.h iris_log.h iris_mtk_api.h iris_lightup.h
iris_loop_back.h iris_gpio.h iris_lp.h iris_uapi.h iris_frc.h iris_ioctl.h`
dll. Di-`obj-` masuk `mediatek-drm-y` (Makefile baris 78-93).

### 7.4 Kelayakan port Iris (terukur)

API 6.4+ yang dihapus — hampir tidak ada:

```
class_create 0   strlcpy 0   timer_setup 0   kernel_read 0
get_user_pages 0  proc_create 0  i2c_new_dummy 0  mipi_dsi_dcs_write 0
```

Hanya `gpio_set_value` (3) dan `of_get_named_gpio` (4), dua-duanya tidak dihapus.

Semua header dependensi ada di tree 6.12 kita:

```
mtk_drm_drv.h mtk_drm_crtc.h mtk_drm_ddp_comp.h mtk_drm_ddp.h
mtk_drm_mmp.h mtk_drm_trace.h mtk_debug.h mtk_panel_ext.h
mtk_log.h mtk_drm_debugfs.h drm_internal.h(kernel)   -> semua present
```

`struct dsi_panel` (sisa Qualcomm) muncul 4x, **semuanya di dalam `#if 0`** —
dead code, sudah diverifikasi per-baris. Tidak perlu diapa-apakan.

Struct `mediatek_v2` yang disentuh iris cuma sedikit:

```
struct mtk_ddp_comp    (2x)
struct mtk_panel_params (1x)  -> lcm_esd_check_table  (ADA di 6.12, baris 577)
struct mtk_panel_ext   (1x)   -> ->params  (ADA)
struct mtk_drm_crtc    (1x)
```

Ini yang membuat port Iris terbatas: iris sebagian besar mandiri (I2C/I3C,
GPIO, firmware load, LUT sendiri) dan menyentuh MTK DRM lewat API sempit.

### 7.5 Langkah Phase 3

**Status 2026-11-19: langkah 1 SELESAI — Iris sudah ter-compile dan link.**

Iris dimasukkan ke `mediatek_v2/v1/` (tempat `mediatek_drm_v1.ko` dibangun),
bukan ke `mediatek_v2/`, supaya persis sama dengan layout modul di device.
16 `.c` + 18 header, masuk daftar `srcs` `mediatek_drm_v1` di BUILD.bazel.

Hasil verifikasi: kesembilan simbol yang dibutuhkan panel
(`iris_enable`, `iris_disable`, `iris_reset`, `iris_reset_off`,
`iris_set_valid`, `iris_is_pt_mode`, `iris_panel_cmd_passthrough`,
`iris_conver_one_panel_cmd`, `iris_loop_back_validate`)
**semuanya EXPORTED** dari `mediatek_drm_v1.ko` hasil build kita.

#### Patch yang diperlukan (semua terukur, 6 iterasi build)

| # | Masalah | Perbaikan | Jumlah |
|---|---|---|---|
| 1 | `strlcpy` dihapus di 6.x | → `strscpy` | 14 |
| 2 | `PXLW_IRIS` tidak didefinisikan, jadi `iris_uapi.h` kosong → 40+ error `msmfb_*` | `local_defines += CONFIG_PXLW_IRIS=1, PXLW_IRIS5=1` | 1 |
| 3 | `struct mipi_dsi_msg` OPPO punya `ctrl`+`wait_ms`; kernel 6.12 stock tidak | buang 2 initializer kosong | 64 |
| 4 | `platform_driver.remove` / `i2c_driver.remove` kembali `void` | ubah tipe + buang `return` | 5 |
| 5 | `i2c_driver.probe` kehilangan argumen `i2c_device_id` | ubah signature | 2 |
| 6 | `params->oplus_cmdq_pkt_set_event` field OPPO-only | guard `&& 0` | 3 |
| 7 | `DISP_SLOT_IRIS_READ_BASE` tidak ada di `mtk_drm_crtc.h` MTK | tambah define (nilai dari OPPO `mtk_drm_crtc.h`) | 1 |
| 8 | `MIPI_DSI_MSG_LASTCOMMAND` di-comment | aktifkan define | 1 |
| 9 | `iris_dsi_pre_cmd/pos_cmd` dideklarasikan + dipanggil tapi tak ada definisi | tambah 2 wrapper di `mtk_dsi.c` | 2 |
| 10 | `vmalloc`/`vzalloc`/`vfree` tidak diekspor ke modul di 6.12 | → `kvmalloc`/`kvzalloc`/`kvfree` (+ `GFP_KERNEL`) | 59 |
| 11 | `int func()` tanpa void | → `(void)` | 1 |

Catatan penting soal #3: nama `dsi_mode_info`, `dsi_cmd_set_state`,
`iris_cmd_desc` memang berbau Qualcomm, **tapi semuanya didefinisikan sendiri
oleh `iris_def.h`**. Yang benar-benar tipe Qualcomm cuma 26 referensi, dan
**semuanya di dalam `#if 0`** — dead code, tidak perlu disentuh.

#### Langkah berikutnya di Phase 3

**Status 2026-11-19: langkah 2 SELESAI — panel rm69220 ter-build.**

`panel-rm69220-vdo-x6871.ko` (631 KB) masuk output, total 1.408 → 1.410 `.ko`.
Basis: `rm692j0_..._lj9.c` dari donor mt6897 — keluarga RM692xx sama,
23 dari 27 fungsi cocok dengan `rm69220` di firmware X6871.

Compatible string cocok persis dengan device:
`rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871`

**Data yang di-recover dari firmware** (tidak ada source publik — GitHub code
search hanya menemukan `panel-raydium-rm69220.c` mainline, bukan MTK):

| Data | Simbol di `.ko` | Hasil |
|---|---|---|
| Init table | `lcm_initialization_setting` | 63 entri, format `{u32 cmd; u8 count; u8 para[251]}` |
| Timing 4 mode | `.rodata` + relokasi `lcm_get_modes` | lihat tabel bawah |
| DSC params | `ext_params_144hz` | 10bpc, 128bpp, pic 1080×2436, slice 540×12, chunk 540 |

Timing hasil decode (semua 1080×2436):

| Mode | clock | HFP | HSA | HBP | VFP | VSA | VBP | htotal | vtotal |
|---|---|---|---|---|---|---|---|---|---|
| 144Hz | 403992 | 24 | 4 | 16 | 40 | 4 | 16 | 1124 | 2496 |
| 120Hz | 368928 | 120 | 4 | 16 | 64 | 4 | 16 | 1220 | 2520 |
| 60Hz | 368928 | 120 | 4 | 16 | 2584 | 4 | 16 | 1220 | 5040 |
| 40Hz | 368732 | 120 | 4 | 16 | 5100 | 4 | 16 | 1220 | 7556 |

Cara decode struct `drm_display_mode` di `.rodata`: cari relokasi
`R_AARCH64_ADR_PREL_PG_HI21` ke `.rodata` di dalam `lcm_get_modes`
(offset 0x1d0/0x248/0x2c0/0x338), lalu baca field sebagai **u16** mulai
offset 4: hdisplay, hsync_start, hsync_end, htotal, (skip), vdisplay,
vsync_start, vsync_end, vtotal. `clock` = u32 di offset 0.

#### Patch 6.1 → 6.12 untuk panel

| Masalah | Perbaikan |
|---|---|
| `{0x11, 0, {0x}}` — brace kosong | `{0}` |
| `struct tran_panel_driver_params` tidak ada di `mtk_panel_ext.h` 6.12 | definisikan lokal di file panel |
| `.tran_panel_params` designator tidak ada | dibuang |
| `.lcm_power_set` callback dihapus di 6.12 | dibuang, fungsi ditandai `__maybe_unused` |
| `.hbm_set_cmdq_switch` dihapus di 6.12 | dibuang, idem |
| `struct lcm` tak punya `dsi`/`dcs_write_gce`/`handle` | init table ditulis sebagai `lcm_dcs_write_seq_static()` |

#### Sisa Phase 3

3. Port panel `ili7838e` (CMD+DSC) — ada di donor 6.1 **dan** w1vo 6.12.
4. DT: node `panel1@0` + GPIO/regulator sesuai `frag0.dts`.
5. Pasang firmware `iris5.fw` + `pxlw-rm69220_..._x6871.fw` ke image.

Belum: panel belum pernah dijalankan di device.

Catatan mode: `rm692j0` (donor 6.1) itu **CMD 1260x2800**, sedangkan
`rm69220` X6871 **VDO RAMLESS 1080x2400**. Beda drive mode — jangan pakai
rm692j0 sebagai basis struktur, pakai rm692h5 (VDO) atau template VDO lain.

### 7.6 Data yang sudah diekstrak dari firmware

`.ko` firmware sudah di-strip debug info, tapi `.rodata` dan nama simbol masih
utuh — cukup untuk mengambil tabel init. Contoh `rm69220_..._x6871.ko`:

```
lcm_probe                 1232 B
lcm_prepare                832 B
lcm_enable                 140 B
mtk_panel_ext_param_set    280 B
panel_ext_lcm_power_set    792 B
```

Ini satu-satunya bagian yang benar-benar RE, dan sifatnya **ekstraksi data**
(tabel perintah DSI, timing, gamma), bukan dekompilasi logika.

---

## 8. Urutan kerja yang disarankan

| # | Kerjaan | Biaya | Risiko | Hasil |
|---|---|---|---|---|
| 1 | Tingkat A: nyalakan `entry_level_legacy.config` | 1 build | rendah | +12 modul, sekaligus validasi loop build varian |
| 2 | Tingkat C: port stack charging Transsion | sedang | sedang | +38 modul |
| 3 | Phase 3: vendor Iris + port panel rm69220 | besar | **tinggi** | device bisa nyala |
| 4 | Tingkat B: rename fpsgo/game | kecil | rendah | +2 |
| 5 | Tingkat D: cari donor Transsion 6.12 | ? | ? | ~55 |

Phase 3 didahulukan secara logika (tanpa panel tidak boot), tapi Tingkat A
layak dikerjakan lebih dulu karena murah dan memvalidasi bahwa
`SUPPORT_PLATFORM=mt6895` + `DEFCONFIG_OVERLAYS` bisa dipakai bersamaan.
Jawaban itu menentukan semua langkah berikutnya.

---

## 9. Aset yang sudah diunduh (di `/serverhive1/ramabondanp/tmp/`)

| Path | Ukuran | Isi |
|---|---|---|
| `mt6897-full.tar.gz` | 1,7 G | donor Transsion/MTK (kernel 6.1, mt6897) |
| `mt6897/` | 4,7 G | hasil ekstrak |
| `x6871/boot.out/kernel` | 18 M | kernel X6871 (LZ4) |
| `x6871/vb.out/` | 33 M | vendor_boot: 237 `.ko` + DTB |
| `x6871/vr/root/lib/modules/` | — | 237 `.ko` siap analisa |
| `x6871/frag0.dts` | 113 K | DTBO X6871 (sumber kebenaran hardware) |
| `x6871-files.txt` | 728 K | 12.897 path firmware X6871 |
| `iris-src/` | 292 K | 16 file source Iris mt6895 (OnePlusOSS) |
| `gap-ko.txt` | 4 K | 107 selisih modul |

Untuk mengulang: `bootRE/ikconfig` (220 K) berisi config kernel device —
bisa dipakai membandingkan `CONFIG_*` kita vs device.

---

## 10. Yang belum terbukti

- **Runtime**: campuran modul Moto + donor OPPO **belum pernah di-boot**.
  Ini berlaku juga untuk hasil Phase 3 nanti.
- `mt6991` / `mt6993`: kabel sudah ada, belum pernah dibangun.
- Tingkat A: belum pernah dibuild dengan `entry_level_legacy.config`.
- Iris: belum pernah dikompilasi terhadap `mediatek_v2` 6.12. Drift struct
  diperkirakan kecil (§7.4) tapi belum dibuktikan dengan compiler.
- Target ABI `user_customer_abi` tidak bisa lulus di tree ini (328 simbol
  duplikat antar varian driver, gagal di `stg merge`). Bukan mismatch KMI.
  Lihat `HANDOFF.md`.

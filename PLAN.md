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
| sudah dibangun w1vo | **439** (80%) |
| selisih | 107 |

107 selisih itu dipecah 4 tingkat:

| Tingkat | Isi | Jumlah | Sifat pekerjaan |
|---|---|---|---|
| **A** | sudah ada target Bazel di tree w1vo, cuma dimatikan config | **12** | satu flag |
| **B** | sudah dibangun tapi beda nama (`fpsgo`→`mtk_fpsgo_v3/v8`, `game`→`mtk_game`) | **2** | rename |
| **C** | source GPL-2.0 ada di donor mt6897 (kernel 6.1) | **38** | port 6.1→6.12 |
| **D** | tidak ada di mana pun | **~55** | cari donor / RE |

---

## 3. Tingkat A — 12 modul, cuma perlu flag

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

12 modul yang jadi hidup:

```
emi-mpu-hook-v1   emi-mpu-v2          mtk-lpm-dbg-common-v1-legacy
mtk-lpm-dbg-mt6895-legacy             mtk-lpm-legacy
mtk-lpm-plat-v1-legacy                mtk-swpm-dbg-common-v1-legacy
mtk-swpm-legacy   mtk-swpm-perf-arm-pmu-legacy
mtk_cm_ipi_legacy_v1                  mtk_cm_mgr_legacy_v1
mtk_cm_mgr_mt6895
```

Bukti sudah lengkap: `mgk_64.bzl` baris 2136 punya blok `if "entry_level.config"
in DEFCONFIG_OVERLAYS:` yang menambah/menghapus label ini; semua Kconfig-nya
ada di tree (`cm_mgr_legacy_v1/Kconfig`, `lpm_legacy/Kconfig`,
`swpm_legacy_v2/Kconfig`, `drivers/memory/mediatek/Kconfig`).

**Langkah:** build dengan
`--repo_env=DEFCONFIG_OVERLAYS=kernel/configs/entry_level_legacy.config`,
lalu diff daftar `.ko` terhadap 107 selisih. Harus nambah 12.

Catatan: `entry_level_legacy.config` juga mematikan beberapa hal
(`# CONFIG_MTK_MBRAINK_* is not set`, `# CONFIG_MTK_CM_MGR is not set` dll).
Perlu dicek bahwa mt6895 tidak butuh yang dimatikan itu.

---

## 4. Tingkat B — 2 modul, rename

`fpsgo` dan `game` sudah dibangun sebagai `mtk_fpsgo_v3`, `mtk_fpsgo_v8`,
`mtk_game`. Firmware menamai `.ko`-nya beda. Tidak ada pekerjaan source.
Perlu dicek apakah ada yang meng-`request_module("fpsgo")` — kalau iya,
sediakan symlink/alias di `.ko` atau di userspace.

---

## 5. Tingkat C — 38 modul, port dari donor mt6897

Donor: `android15_kernel_modules_and_devicetree_mt6897.tar.gz` (1,7 GB,
sudah diunduh dan diekstrak). Isinya kernel 6.1 / mt6897, **bukan** base
build — salah generasi kernel dan tidak ada satu pun path `mt6895` di dalamnya.
Fungsinya murni pemasok source.

Yang paling berharga: **stack charging Transsion**, GPL-2.0, lengkap.
`drivers/power/supply/transsion/` berisi 84 file. Ini menutup ~38 modul:

```
tc_adapter_class      tc_algorithm_class   tc_ambient_temp_det
tc_audio              tc_auto_test         tc_charger_class
tc_charger_framework  tc_chg_type_det      tc_common_class
tc_gauge              tc_hl7139a           tc_lcd_notify
tc_misc_intf          tc_otg_ctrl          tc_pd_adapter
tc_pd_algo            tc_pep50             tc_phy_insert_det
tc_pid_chg_algo       tc_pmic              tc_port_corrosion_prevention
tc_ta_class           tc_tcpc              tc_temp_forecast
tc_water_detect       tran_audio_control   tran_charge_transfer
tran_usb_ctrl         aw36515              hiber
leds-aw22xxx          nfc_i2c              snd-soc-aw87xxx
snd-soc-fs1599        snd-soc-oca72xxx     splitswitch-gpio
elliptic-ultrasound   mtk_cm_mgr_mt6895
```

Penting: nama modul di firmware datang dari entri `obj-*` di Makefile, bukan
dari nama file. Contoh `tc_charger_framework` = `tc_charger.o + tc_charger_intf.o
+ tc_charger_attr.o + tc_basic_charger.o + tc_voter.o`. Jadi jangan cari file
`tc_charger_framework.c` — tidak ada.

### Biaya port 6.1 → 6.12 (terukur)

Sudah discan pemakaian API yang dihapus di 6.4+:

```
class_create   11   (hanya yang signature-nya berubah: THIS_MODULE hilang)
strlcpy         0
timer_setup     0
kernel_read     0
get_user_pages  0
proc_create     4
i2c_new_dummy   0
```

`power_supply_*` stabil di batas 6.1/6.12 (13 register, 26 changed, 53 get, 24 set).
Jadi pekerjaan mekanis: hapus argumen `THIS_MODULE` di 11 `class_create`.

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

1. **Vendor iris** ke
   `kernel_device_modules-6.12/drivers/gpu/drm/mediatek/mediatek_v2/`,
   tambahkan ke `mediatek-drm-y` di Makefile. Dengan begini iris ikut
   ter-compile ke `mediatek_drm_v1` — sama persis dengan layout modul di device.
2. **Perbaiki drift struct** terhadap `mediatek_v2` 6.12. Ini satu-satunya
   tugas yang ukurannya belum pasti, tapi terbatas: file-set tetap, API sempit
   (§7.4).
3. **Port panel rm69220** (VDO + RAMLESS + 144Hz). Basis struktur:
   `panel-rm692h5-cmd.c` (sudah native 6.12, keluarga RM692xx sama, 1858 baris).
   Tabel init diambil dari `.ko` firmware.
4. **Port panel ili7838e** — ada di donor 6.1
   (`ili7838e_fhdp_dsi_cmd_tm_tm_120hz_d9300.c`, 2025 baris) **dan** di w1vo
   6.12 (`panel-ili7838e-dv3-alpha-cmd.c`, 1306 baris). Ini paling dekat:
   ganti tabel panel + compatible string. CMD+DSC sama dengan varian `cl9`.
5. **Register di build**: `panel/Makefile`, `panel/Kconfig`, `mgk_64.bzl`.
6. **DT**: node `panel1@0` dengan
   `compatible = "rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871"`,
   plus GPIO/regulator sesuai `frag0.dts` hasil ekstrak `dtbo.img`.

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

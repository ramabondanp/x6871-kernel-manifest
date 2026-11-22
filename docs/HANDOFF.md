# HANDOFF — W1VO36 / X6871 kernel device modules

Ditulis 2026-11-19, diperbarui 2026-11-22 sebagai referensi teknis & panduan kelanjutan proyek. Baca ini dulu, lalu `PLAN.md`
(bagian §6.1b, §6.2k, §6.2m, §6.2n, §6.2o, §6.2p, §6.2q, §6.2r, §6.2s,
§6.2t, §6.2u) dan `PRETEST.md`.

## Status ringkas

| Item | Nilai |
|---|---|
| GKI base (`kernel-6.12`) | AOSP murni `android16-6.12-2026-09_r16` (`6.12.92-android16-6-g7cc745542612-4k`, **KMI 6**, tanpa patch) |
| `.ko` flat customer install | **419** (di-trim via `kernel/kleaf/x6871_modules.bzl` ke **413** target OOT X6871; sebelumnya 679) |
| `.ko` di staging (file / nama unik) | **553 / 552** (`mtk-socinfo` dobel; sebelumnya 813 / 812; action Bazel `4.867 → 919`) |
| Modul di firmware X6871 | 237 (`vendor_boot`) + 288 (`vendor_dlkm` + `odm_dlkm`) |
| Nama stock `vendor_boot` tidak ada di build | **20** (6 tidak direncanakan, 14 kandidat) |
| Modul recovery `vendor_boot` | **222**, 100% source (KMI 6) |
| DLKM (`vendor_dlkm` + `odm_dlkm`) | **266** (`209` + `57`), 100% source (KMI 6, bebas `CONFIG_MODULE_SIG_PROTECT`), image siap |
| Build target | `//kernel_device_modules-6.12:mgk_64_k612_customer_modules_install.user` |
| Build terakhir | sukses (clean KMI 6 + trimmed X6871 allowlist), 2026-11-22 |
| Kernel HEAD | `fa18f7f` (`alps-kernel_device_modules-6.12`, `x6871-android16-6.12`, 106 commit di atas `06079c2`) |
| Vendor MTK modules HEAD | `83b4fa6` (`alps-vendor_mediatek_kernel_modules`, `x6871-android16-6.12`) |
| Active clean workspace | `~/x6871-kernel` |
| Runtime | **Lulus boot di GKI KMI 6 (`android16-6.12-2026-09_r16`, `v19-kmi6`)** dengan `boot.img` + `system_dlkm.img` resmi Google (0 mismatch CRC vs `abi.stg` `10.630` simbol, 0 kolisi `CONFIG_MODULE_SIG_PROTECT`, 0 unresolved symbol); seluruh subsistem modul sebelumnya lulus di KMI 5 (`v18`) |

## Status Rilis Terbaru & Ringkasan Riwayat (2026-11-22)

### Rilis terbaru: `gki-kmi6-20261122` (GKI `android16-6.12-2026-09_r16`, kernel `20a8f5d`, `vendor_boot` v19-kmi6)

```text
x6871-twrp-vendor_boot-v19-kmi6.img  md5 91eb249ff001d250fad855c40476f1b5  67.108.864 B
vendor_dlkm.img                      md5 5f7b6cecb1c44a1ffc3280dd481fbfcf  24.551.424 B
odm_dlkm.img                         md5 6ee3cadceb5c4750dbbfe3d0056b6ea8   4.206.592 B
/srv path                            ~/x6871-out/
rollback KMI 5                       x6871-twrp-vendor_boot-v18.img, vendor_dlkm-v16-kmi5.img, odm_dlkm-v16-kmi5.img
```

Migrasi GKI ke tag AOSP murni **`android16-6.12-2026-09_r16`** (`6.12.92-android16-6`, `KMI_GENERATION=6`, `CLANG_VERSION=r536225`, `RUSTC_VERSION=1.82.0.p2`) **tanpa mengubah satu baris pun di `kernel-6.12`** (`PRETEST.md` §68):
1. **`kernel/kleaf/mgk_modules.bzl` (`96b299e`)**: filter `fs/pstore/pstore_blk.ko` & `fs/pstore/pstore_zone.ko` dari `mgk_module_{eng,userdebug}_outs` bila sudah masuk `COMMON_GKI_MODULES_LIST` di `kernel-6.12/modules.bzl`.
2. **`drivers/misc/mediatek/sched/eas/balance.c` (`20a8f5d`)**: hapus klon lokal `attach_task()` / `attach_one_task()` yang kini disediakan `static inline` di `kernel/sched/sched.h` pada `6.12.92`.
3. **`vendor_dlkm` & `CONFIG_MODULE_SIG_PROTECT`**: keluarkan 3 modul GKI terproteksi (`rfkill.ko`, `bluetooth.ko`, `libarc4.ko`) dari `vendor_dlkm` (kini `209` modul, `191` `modules.load`) karena ketiganya sudah dimiliki & ditandatangani oleh `system_dlkm.img` GKI resmi Google (`zsmalloc.ko` & `zram.ko` di `odm_dlkm` termasuk `_COMMON_UNPROTECTED_MODULES_LIST`, aman).
4. **Verifikasi KMI 6**: 6.418 simbol `abi.stg` berubah CRC dari KMI 5→6 (berdampak ke 491/491 modul); setelah build ulang seluruh 488 `.ko` (`222`+`209`+`57`) mencocokkan **0 mismatch CRC** terhadap `gki/aarch64/abi.stg` resmi (`10.630` simbol), **0 simbol `vmlinux` non-KMI-6**, **0 kolisi `CONFIG_MODULE_SIG_PROTECT`**, dan **0 unresolved symbol**.

### Rilis sebelumnya (KMI 5): `mtu3-stock-20261122` (kernel `32a8db7`, `vendor_boot` v18)

```text
x6871-twrp-vendor_boot-v18.img  md5 73b94a9f88ed39a852e8a1343978d37e  67.108.864 B
vendor_dlkm.img                 md5 72daa1f10eba75d9cd0e3359a27ff76f  24.551.424 B
odm_dlkm.img                    md5 99b2194fa63cab8c751f71b8fbd4eb5e   4.206.592 B
/srv path                       ~/x6871-out/
```

Audit v17 (`6230061`) terhadap `mtu3.ko` stock dan `common-6.12/drivers/usb/gadget/udc/core.c`
membuktikan `usb_gadget_connect()` di `ssusb_mode_sw_work_v2()` bukan perilaku stock dan akan
selalu no-op untuk seluruh jalur Android yang mematikan pullup (unbind configfs, FunctionFS
`unregister_gadget_item()`, `soft_connect disconnect`, atau deactivate).

Commit `32a8db7` (hasil squash dari revert `6230061` + `f661c15`) menyamakan `mtu3.ko` dengan binary stock X6871:
1. Tambah `mdelay(4)` pada `mtu3_dev_on_off(is_on=0)` (identik `__const_udelay(0x1062560)` stock di `mtu3_dev_on_off` & `mtu3_stop`).
2. Tambah `ssusb_phy_dp_pullup()` di `mtu3_stop()` saat `!softconnect && !is_gadget_ready` (dijaga `dp_work.func` agar bebas `WARN_ON` saat probe).
3. Pindahkan penghapusan properti DT `cdp-block` dari `mtu3_gadget_pullup()` ke `ssusb_gadget_init()` sesuai stock (`mtu3_dev_on_off` `0x15c`, `mtu3_gadget_pullup` `0x2a8`, dan `ssusb_mode_sw_work_v2` `0x2e0` kini identik ukuran dengan stock).

**Hasil uji v18 (`dmesg10.txt`/`logcat10.txt`) & isolasi akar masalah:**
- `dmesg10.txt` menunjukkan `mtu3_gadget_pullup (off)` kembali terpicu saat `adbd` restart (`30.537`–`30.595`, 7,4 detik sebelum kabel pertama kali dicabut di `37.978`).
- Pengguna mem-flash kembali **seluruh DLKM dan modul stock** di atas kernel GKI custom yang sama dan **bug tetap terjadi secara identik** — membuktikan akar masalah berasal dari **kernel GKI custom (`boot.img`)**, bukan dari modul `vendor_boot`/`vendor_dlkm`/`odm_dlkm` kita (`PRETEST.md` §67). Investigasi USB pada sisi modul ditutup/di-skip.

### Rilis sebelumnya (dibatalkan/di-squash): `mtu3-replug-20261122` (kernel `6230061`, `vendor_boot` v17)

```text
x6871-twrp-vendor_boot-v17.img  md5 68df06607016a34d12bfbe19e2c6df77  67.108.864 B
vendor_dlkm.img                 md5 72daa1f10eba75d9cd0e3359a27ff76f  24.551.424 B
odm_dlkm.img                    md5 99b2194fa63cab8c751f71b8fbd4eb5e   4.206.592 B
/srv path                       ~/x6871-out/
```

Digantikan oleh v18 (`32a8db7`, di-squash dari `6230061`+`f661c15`) karena `usb_gadget_connect()` terbukti no-op dan non-stock (`PRETEST.md` §65–§67).

### Rilis sebelumnya: `rcv-usb-20261122` (kernel `68db913`, `vendor_boot` v16 + DLKM v15)

```text
x6871-twrp-vendor_boot-v16.img  md5 b6a0fb64f1043314a990b420af0c163b  67.108.864 B
vendor_dlkm.img                 md5 72daa1f10eba75d9cd0e3359a27ff76f  24.551.424 B
odm_dlkm.img                    md5 99b2194fa63cab8c751f71b8fbd4eb5e   4.206.592 B
/srv path                       ~/x6871-out/
```

Hasil uji v14 (`dmesg8.txt`/`logcat6.txt`): **charging HVDCP20/PD LULUS, tidak ada panic**. Dua bug sisa diperbaiki (`PRETEST.md` §64):
1. **Earpiece speaker (`snd-soc-mt6368.ko`, `aca5276`)**: modul stock punya pilihan `RCV Select=Playback_R_DAC` + route `RCV Mux/Playback_R_DAC/DACR`, `RCV Mux/Test Mode/LINEOUT L`, serta `mt_rcv_event()` yang memprogram DACR (`CON0=0x6`, `CON11=0x97`), DACL (`CON0=0x9`, `CON11=0x9b`), atau Test Mode (`0x9f`) sesuai mux. Build kita hanya punya `Voice Playback->DACL` dan selalu memprogram DACL, sehingga `mt_rcv_event()` tidak pernah jalan saat HAL memilih `Playback_R_DAC`. Enum/route/event disamakan dengan stock; route `.rodata` hasil build kini identik stock.
2. **USB replug — UDC tidak pullup (`tran_extcon_usb.ko`, `68db913`)**: `vbus_gd` sekarang terbaca (`switch ic vbus_gd is ready`) tetapi setelah role DEVICE tidak ada `mtu3 ... gadget pullup D+`/enumerasi. Stock memakai `system_power_efficient_wq` untuk `wq_psy`, `WQ_HIGHPRI|WQ_UNBOUND` untuk `extcon_wq`, dan menulis `c_role` setelah `usb_role_switch_set_role()`. v13 mengubah ketiganya; dikembalikan ke stock. Sisa risiko: `tran_extcon_pd_tcpc_notifier()` stock (588 B) menangani `TC_PD_TYPE`/DR-swap, belum diport.

### Rilis sebelumnya: `iommu-chg-earpiece-usb-20261122` (kernel `5f569d0`, `vendor_boot` v14 + DLKM v13)

```text
x6871-twrp-vendor_boot-v14.img  md5 c5236194d20621543af6eb14a20e9e7b  67.108.864 B
vendor_dlkm.img                 md5 378d9adf1de9c5a2d3fa8d8466aefd29  24.551.424 B
odm_dlkm.img                    md5 d6bb4ed087c9f9f69a96c8687c816b2c   4.206.592 B
/srv path                       ~/x6871-out/
```

Perbaikan tambahan v14 (`PRETEST.md` §63, dari `pstore2.txt`):
- **Boot-time race panic di `mtk_iommu.ko` (`5f569d0`)**: `mtk_iommu_probe()` sebelumnya memanggil `iommu_device_register()` sebelum menginisialisasi `data->hw_list` dan `data->tlb_lock`, sehingga probe paralel `1e990000.gce` mendapat `hw_list is NULL` (`-ENODEV`) lalu `mtk_iommu_release_device()` memanggil `device_link_remove(dev, NULL)` (NULL deref di `0xe0`). Kini `hw_list`/`tlb_lock` diinisialisasi sebelum `iommu_device_register()` dan `larbdev` dijaga NULL/bounds. (`vendor_dlkm.img` & `odm_dlkm.img` tidak berubah dari v13.)

### Rilis sebelumnya: `chg-earpiece-usb-20261122` (kernel `8944601`, `vendor_boot` v13 + DLKM)

```text
x6871-twrp-vendor_boot-v13.img  md5 242333a0cc953a3804c593e388984d24  67.108.864 B
vendor_dlkm.img                 md5 378d9adf1de9c5a2d3fa8d8466aefd29  24.551.424 B
odm_dlkm.img                    md5 d6bb4ed087c9f9f69a96c8687c816b2c   4.206.592 B
/srv path                       ~/x6871-out/
```

Hasil uji v12 (`dmesg7.txt`/`logcat5.txt`/`pstore1.txt`): **screen-off FOD, DT2W, dan flashlight LULUS**. 3 bug baru diperbaiki di v13 (`PRETEST.md` §62):
1. **Panic saat charging dengan adapter (`tc_charger_framework.ko`, `0af45b1`)**: `alg_id_enum` / `alg_name_array[]` di `tc_charger.h` hanya berisi 4 entri (`none`, `pe5`, `pd`, `pe20`) tanpa `tc30`/`hvdcp20`, sehingga `tchg_alg_id("hvdcp20")` mengembalikan `-22` dan `Pump_Express_show` mengindeks `alg_name_array[-22]` (UBSAN panic di `pstore1.txt`). Samakan 6 entri stock (`none`, `pe5`, `tc30`, `pd`, `hvdcp20`, `pe20`), tambah switch `TC30_ID`/`HVDCP20_ID`, dan beri bounds check `tchg_alg_id_to_name()`.
2. **Earpiece speaker mati (`mt6895-mt6368.ko`, `22efa7e`)**: `mt6895_mt6368_routes[]` kekurangan rute stock `{EXT_SPK_AMP_W_NAME, NULL, "RCV Mux"}` sehingga `mt_rcv_event()` tidak pernah aktif.
3. **USB replug tidak terdeteksi (`mt6375-charger.ko` + `tran_extcon_usb.ko`, `8944601`)**: `mt6375_chg_ops` tidak memiliki `.get_vbus_gd` (`mt6375_get_vbus_gd_stat` → `F_ST_PWR_RDY`), sehingga `tc_detect_bc12_run` mendapat `-95` dan langsung menjalankan BC1.2 tanpa menunggu VBUS good + `msleep(100)`. Tambah `mt6375_get_vbus_gd_stat`, bersihkan `tc_bc12_dn` sebelum re-enable BC1.2, dan antrekan `wq_psy` di `extcon->extcon_wq`.

### Rilis sebelumnya: `sofod-dt2w-flash-20261122` (kernel `ebca3e1`, `vendor_boot` v12 + DLKM)

```text
x6871-twrp-vendor_boot-v12.img  md5 f345308a330b4ceb5daf586bcd059607  67.108.864 B
vendor_dlkm.img                 md5 4cb91f7c318d0960289e86fe764448e5  24.551.424 B
odm_dlkm.img                    md5 411cc6106caedd526767e9f5cfc5a70d   4.206.592 B
/srv path                       ~/x6871-out/
```

Hasil uji v11 (`dmesg6.txt`/`logcat4.txt`): **FOD saat AOD LULUS** (layar tidak lagi rusak). Sisa 3 bug diperbaiki di v12 (`PRETEST.md` §61):
1. **Screen-off FOD saat AOD padam (`panel-rm69220-vdo-x6871.ko`, `0d456ba`)**: Hapus `gpiod_set_value(ctx->vddi_gpio, 0)` di `panel_ext_lcm_power_set(on == 0)` agar sesuai stock RM69220; rail `vddi-gpios` (1,8 V) menyuplai Goodix GT9916 sehingga menurunkannya memutus daya IC touch saat AOD mati.
2. **DT2W (`adaptive-ts.ko`, `e4ed999`)**: Android menulis `"cc1"` lalu `"al2"` (`0xff`) 1 ms kemudian saat boot; batasi toggle `tran_gesture_enable()` hanya pada `code == 0xcc` agar `"al2"` tidak menonaktifkan `GESTURE_DOUBLE_TAP_BIT`.
3. **Flashlight (`flashlight.ko` + `ocp81375_v4l2.ko`, `ebca3e1`)**: V4L2 subdev kini sudah terbuka saat tombol senter ditekan, tetapi `CONFIG_MTK_FLASHLIGHT_PT` / `PT_STRICT` memicu `pt_trigger` pada SOC <= 15% dan membuat `FLASH_IOC_IS_LOW_POWER` mengembalikan `2`. `#undef` kedua makro di `flashlight-core.h` agar cocok dengan stock `flashlight.ko` & `ocp81375_v4l2.ko` (0 simbol PT).

### Rilis sebelumnya: `aod-dt2w-flash-20261122` (kernel `78a1441`, `vendor_boot` v11 + DLKM)

```text
x6871-twrp-vendor_boot-v11.img  md5 f61e734b13b8f95967278f0dd5f61cd6  67.108.864 B
vendor_dlkm.img                 md5 ffa1ce1106b022a5c9397fe5b5d82ff0  24.551.424 B
odm_dlkm.img                    md5 88307f5b15ff51b0cce511fb5d1a7427   4.206.592 B
/srv path                       ~/x6871-out/
```

Hasil uji v10 (`dmesg5.txt`/`logcat3.txt`): rekam video & optical FOD normal **LULUS**. Sisa 3 bug diperbaiki di v11 (`PRETEST.md` §60):
1. **FOD saat AOD layar rusak (`panel-rm69220-vdo-x6871.ko`, `59ed7e7`)**: Hapus `aod_mode_enter_setting` (`0x39` hardware 8-color Idle Mode) dan `aod_mode_exit_setting` (`0x38`/`0x51`) dari `panel_hbm_set_cmdq()`, samakan dengan stock RM69220 (2-entry HBM table, dimming `{0x53, 0x20}`/`{0x53, 0x28}`, alpha AOD `{0x2E, 0x19}`, dua tabel alpha stock 256 & 248 entry).
2. **DT2W (`adaptive-ts.ko`, `10396cb`)**: `KeyguardGestureManager` (`MicroIntelligence.apk`) membaca `/proc/gesture_function` lewat `FileInputStream.read()` (`count == 1`). `tran_gesture_data_read()` kini memakai `simple_read_from_buffer()` (tidak lagi `-EINVAL` pada `count < 2`) + dukungan 17-entri `gesture_maps` (`cc1`/`cc2` dan `/proc/gesture_state`).
3. **Flashlight (`sgm37864_v4l2.ko` + `ocp81375_v4l2.ko`, `78a1441`)**: `mtk_composite` menunggu kedua endpoint (`ocp81375_v4l2/flash@0` dan `sgm37864_v4l2/flash_sgm37864@0`) sebelum mendaftarkan `/dev/v4l-subdev*`. `sgm37864.c` kini mencari child DT `"flash_sgm37864"` + nama subdev `"sgm37864_v4l2-led*"` sesuai stock; `ocp81375.c` memakai `ocp81375_mode_ctrl()` di `V4L2_CID_FLASH_LED_MODE` + fallback `FLASH_IOC_SET_DUTY`.

### Rilis sebelumnya: `venc-fod-dt2w-20261122` (kernel `17a6b66d7927`, `vendor_boot` v10 + DLKM)

```text
twrp-vendor_boot-allsrc-display-usb-v10.img  md5 3409f68913613b38d43052458435558b  67.108.864 B
vendor_dlkm.img                              md5 764c2d3f6fbd14aff802a0614ec7d014  24.551.424 B
odm_dlkm.img                                 md5 af60243be2a87943f78fc7d254bb690a   4.206.592 B
twrp-dlkm-venc-fod-dt2w-20261122.zip         md5 92ab587de697a955fceba15ecf335d52
/srv path                                    ~/tmp/dlkm-out/ (+ tmp/x6871/)
```

Boot pembanding `normal2.txt` (GKI `Image` kita + modul stock) berhasil merekam video 1080p, DT2W saat AOD, dan FOD — memastikan seluruh bug ada di modul kita (`PRETEST.md` §59):

1. **Rekam video / VENC (`mtk-vcodec-enc.ko`, `17a6b66d7927`)**: `normal2.txt` mencetak `check_codec_id ipi id 1 is correct` saat init VENC, sedangkan `dmesg3`/`dmesg4` tidak pernah mencetaknya. Di `mtk_vcodec_drv.h`, `VENC_H264..VENC_H263` menyambung enum setelah `VDEC_AV1 (12)` sehingga `VENC_H264 == 13` alih-alih `1`. `check_codec_id()` diam-diam membalas `status=-1`, membuat VCP tidak mengalokasikan buffer ref/rec/comv HW (`0x74..0x88 == 0` → fault `LARB7_PORT24`/`PORT3 mva=0x0` → VCP WDT). Fix: reset `VENC_H264 = 1`, perluas `struct mtk_codec_capability` ke 24 B + kontrol `ADAB_CAPABILITY` 4x `U32`, jalankan `slbc_request()` walau `slbc_register_activate_ops` gagal, cek `msg->status != 0` pada `VCU_IPIMSG_ENC_SET_PARAM_DONE`, dan guard NULL `inst`/`vsi` di `mtk_venc_dvfs_sync_vsi_data`.
2. **DT2W saat AOD (`mediatek_drm_v1.ko` `6b45fdaa1ef1` + `adaptive-ts.ko` `379924bf2586`)**: `mtk_disp_notify.h` kehilangan `TRAN_DISP_BLANK_NOTIFY_FINGERPRINT (2)` sehingga `TRAN_DISP_BLANK_AOD_NOTIFY` bergeser ke `2` (stock `3`). `mtk_dsi_encoder_enable()` belum mengirim `TRAN_DISP_BLANK_AOD_NOTIFY`, dan `adaptive-ts` ikut resume pada `MTK_DISP_BLANK_UNBLANK (0)` sehingga masuk AOD langsung membangunkan touch dari mode gestur. Fix: samakan enum stock, kirim `TRAN_DISP_BLANK_AOD_NOTIFY (3)` hanya saat `!mtk_dsi_doze_state(dsi)` (unblank penuh / keluar AOD), dan `adaptive-ts` hanya resume pada `TRAN_DISP_BLANK_AOD_NOTIFY (3)`.
3. **Optical FOD (`tran_fp.ko` `55aa13232a43` + `mediatek_drm_v1.ko` `6b45fdaa1ef1` + `gt9916_common.ko` `379924bf2586`)**:
   - `tran_fp`: daftarkan `/dev/goodix_fp` (sebelumnya `"tran_fp"`), set SPI 8-bit/4 MHz/mode 0, aktifkan `tran_fp_irq_init()` (guard NULL pada `irq_init` agar pinctrl `pins_irq` tetap dipilih), dan aktifkan tanpa syarat pengiriman uevent `TRAN_FULL_HBM_EVENT=FULL_HBM_SET` pada `TRAN_DISP_BLANK_NOTIFY_FINGERPRINT (2)`.
   - `mediatek_drm_v1`: kirim `TRAN_DISP_BLANK_NOTIFY_FINGERPRINT (2)` di akhir `mtk_drm_crtc_set_panel_hbm(crtc, true)`.
   - `gt9916_common`: `/proc/fingerprint_status` menulis perintah Goodix `0x30` (`len=5`, `data[0]=0`/`1`), `brl_gesture()` zero-init `cmd`, `brl_event_handler()` mendeteksi FOD down (`0x88`) / up (`(pre_buf[0] & 0xf) == 0`) dengan key `195` (`0xc3`), dan `goodix_ts_resume()` membersihkan `g_fp_flag`.

### Yang sudah terbukti di device (TWRP & Android 16)

- **Boot & recovery**: TWRP + Android 16 boot sampai launcher dengan **222** modul `vendor_boot` (`modules.load` 165, `modules.load.recovery` 216) + **269** modul DLKM (**212** `vendor_dlkm` + **57** `odm_dlkm`, `modules.load` 194/57), 100% source, closure simbol **0 unresolved** (hanya weak `mtk_drm_gateic_set_backlight`).
- **Layar & AOD**: `panel-rm69220-vdo-x6871.ko` (4 mode 144/120/60/40 Hz byte-identik stock, 8bpc/1056 Mbps, 0 underrun) + `mediatek_drm_v1.ko` (C3D dual-pipe SRAM + `PQ_VIRTUAL_SET_PROPERTY` 12 B + AOD).
- **GPU & SCP**: Mali r54p1-11eac0 donor OPPO + fix layout `gpufreq_shared_status` + `SCP_IPI_COUNT=59`.
- **USB, Charger & Audio**: replug USB lulus di uji historis `dmesg14` (§42.1), tetapi gagal pada Android v16 (§65); spam IRQ battery OC 65 Hz ditutup (`rfg-mtk-tran-conf-diff`), earpiece + audio FS1599 PA + `tran_audio_control` normal, haptic + Wi-Fi + UFS/MTK storage + touch normal OK.
- **Kamera foto & preview**: 4 sensor X6871 (`s5khm6sx`, `gc32e1`, `gc02m3`, `gc02m3macro`) + `camera_eeprom_v4l2` + `mtk-cam-isp` inline `sink_fmt` + flashlight `ocp81375_v4l2`.

### Komposisi modul & repack

- **Set `vendor_boot` (222 modul)**: 20 nama stock tidak ada di build (6 tidak direncanakan: panel `cl8`/`ili7838e`, alias panel X6871, 3 MMC/SD; 14 kandidat: 7 storage Transsion, 4 terblokir `transsion_tranlog`, 3 fitur mandiri). Lima modul build-only ditambahkan: `adaptive-ts`, `gt9916_common`, `mtk-mmc`, `panel-rm69220-vdo-x6871`, `tran_richtap_haptic_hv`.
- **Set DLKM (269 modul)**: EROFS identik opsi stock + AVB hashtree footer; zip TWRP menulis langsung ke logical partition tanpa menghapus partisi. 25 modul stock tanpa source (`transsion_tranlog`, `thd`, varian touch alternatif, dll.) tidak disertakan; `tran_zram` diganti `zsmalloc`+`zram`, ditambah `rfkill`, `bluetooth`, `libarc4`, `task_turbo`.
- **Repack `vendor_boot`**: selalu pakai `tools/repack-vendor-boot-latest.sh` (lihat §Perintah build / Repack). Jangan menyalin `.ko` dari image lama atau memakai `tools/pack-vendor-boot.sh` legacy (`PRETEST.md` §43/§44).

### Ringkasan riwayat rilis (`v1`–`v19-kmi6`)

| Rilis | `vendor_boot` | Kernel HEAD | Ringkasan perubahan | Referensi |
|---|---|---|---|---|
| `gki-kmi6-20261122` | v19-kmi6 | `20a8f5d` (`fa18f7f` trimmed) | Migrasi GKI ke AOSP murni `android16-6.12-2026-09_r16` (`6.12.92`, KMI 6, 0 edit GKI), dedup `pstore_{blk,zone}` (`96b299e`), hapus klon `attach_task` di `eas/balance.c` (`20a8f5d`), keluarkan 3 modul GKI terproteksi dari `vendor_dlkm`, + trim allowlist `x6871_modules.bzl` (`fa18f7f`) | `PRETEST.md` §68 |
| `mtu3-stock-20261122` | v18 | `32a8db7` | Revert `6230061` (no-op non-stock) + samakan `mtu3.ko` dengan stock (`mdelay(4)` off, `ssusb_phy_dp_pullup` di `mtu3_stop`, hapus `cdp-block` di `ssusb_gadget_init`) | `PRETEST.md` §66–§67 |
| `mtu3-replug-20261122` | v17 | `6230061` | (Direvert di v18) MTU3 `usb_gadget_connect()` pada NONE → DEVICE | `PRETEST.md` §65 |
| `rcv-usb-20261122` | v16 | `68db913` | Fix earpiece `Playback_R_DAC` (enum/route/`mt_rcv_event`) dan pullup UDC saat replug (workqueue/urutan role switch stock) | `PRETEST.md` §64 |
| `iommu-chg-earpiece-usb-20261122` | v14 | `5f569d0` | Fix boot race panic `mtk_iommu` (`hw_list` sebelum `iommu_device_register` + NULL guard `larbdev`) di atas v13 | `PRETEST.md` §63 |
| `chg-earpiece-usb-20261122` | v13 | `8944601` | Fix panic charging HVDCP20 (`tc30`/`hvdcp20` `alg_name_array` + guard), earpiece speaker (`RCV Mux`), USB replug (`mt6375_get_vbus_gd_stat` + `extcon_wq`) | `PRETEST.md` §62 |
| `sofod-dt2w-flash-20261122` | v12 | `ebca3e1` | Fix screen-off FOD (`vddi-gpios` tetap HIGH), DT2W (`al2` tidak mematikan `0xcc`), flashlight PT throttling (`#undef PT`/`PT_STRICT`) | `PRETEST.md` §61 |
| `aod-dt2w-flash-20261122` | v11 | `78a1441` | Fix FOD di AOD (hapus `0x39` idle mode + tabel alpha RM69220), DT2W 1-byte `simple_read_from_buffer` + `gesture_maps`, V4L2 flashlight (`flash_sgm37864` + `ocp81375`) | `PRETEST.md` §60 |
| `venc-fod-dt2w-20261122` | v10 | `17a6b66d7927` | Fix akar masalah VENC (`VENC_H264=1`, ADAB, SLBC), ABI notifier AOD/HBM, DT2W AOD, `/dev/goodix_fp` + FOD key `195` | `PRETEST.md` §59 |
| `video-touch-20261121` | v9 | `6566cb27da18` | Wake awal IRQ gestur, log VSI VENC, log INFO `tran_fp` | `PRETEST.md` §58 |
| `touchfix-20261121` | v8 | `a453c308cc33` | Kembalikan gate `suspended` `gsx_gesture_ist` + clear gesture event | `PRETEST.md` §57 |
| `qpabi-fpgest-20261121` | v7 | `6b2a88973414` | ABI 6-field QP VENC identik stock, fallback `goodix_opt_tee` | `PRETEST.md` §56 |
| `vid-fl-dt2w5-20261121` | v6 | `3c5e64704b34` | C3D SRAM guard, `ocp81375_v4l2`, DT2W key `198` | `PRETEST.md` §55 |
| `cam4-fod-dt2w-20261121` | v5 | `831ee7ca4762` | Mode video `s5khm6sx` 4000×2248, `vendor_name=goodix_opt_tee` | `PRETEST.md` §54 |
| `dlkm-cam3-dt2w-20261121` | v4 | `466e4c1731c1` | `mtk-cam-isp` inline `sink_fmt`, `s5khm6sx` D-PHY 4-lane, flashlight core, touch gesture | `PRETEST.md` §53 |
| `audio-aod-cam2-20261121` | v4 | `a765870ac11f` | Audio FS1599 PA + AOD/screen-on panel RM69220 | `PRETEST.md` §52 |
| `dlkm-cam1-20261121` | v3 | `75ca1ac4a1ae` | Port 4 sensor kamera X6871 + `camera_eeprom_v4l2` | `PRETEST.md` §51 |
| `vendor-boot-c3dfix-20261121` | v3 | `e84137d0e2aa` | C3D dual-pipe SRAM + `PQ_VIRTUAL_SET_PROPERTY` 12 B (layar normal penuh) | `PRETEST.md` §50 |
| `dlkm-ocfix-20261121` | v2 | `e6d0ab2fb66a` | Battery OC 65 Hz (`rfg-mtk-tran-conf-diff`) + timing switch 144/120/60/40 Hz | `PRETEST.md` §49 |
| `dlkm-20261120`..`gpu3` | v1 | `07eb1dab07c2` | Repack DLKM 100% source (269 modul), `SCP_IPI_COUNT=59`, Mali r54p1, `gpufreq_shared_status` | `PRETEST.md` §45–§48 |

### Langkah verifikasi & pemeliharaan berikutnya

Ikuti `BOOTTEST.md` §3–§4 untuk setiap pembaruan GKI atau modul:

1. **Verifikasi KMI/ABI sebelum flash**: jalankan `./tools/verify-kmi-abi.py` (wajib lulus seluruh 8 gerbang).
2. **Flash pasangan GKI KMI 6 yang serasi**: `x6871-twrp-vendor_boot-v19-kmi6.img` + `vendor_dlkm.img` + `odm_dlkm.img` wajib dipasangkan dengan `boot.img` + `system_dlkm.img` GKI resmi Google `android16-6.12-2026-09_r16`.
3. **Checklist regresi subsistem**: layar 144/120/60/40 Hz & AOD, FOD (layar menyala, AOD, screen-off), DT2W, kamera foto & rekam video 1080p, flashlight, audio speaker & earpiece, Wi-Fi/BT, dan fast charging HVDCP20/PD.

### Catatan kamera, device table & repo

- **Kamera (`PRETEST.md` §26, §51, §53)**: 4 sensor kamera X6871 (`s5khm6sx`, `gc32e1`, `gc02m3`, `gc02m3macro`) + `camera_eeprom_v4l2` sudah diport (`75ca1ac4a1ae`, `scripts/add-camera-x6871.sh`) dan kamera foto + rekam video sudah berjalan. Yang tidak dipublikasikan vendor hanya 46 fungsi kalibrasi OTP per sensor di `camera_eeprom_v4l2` dan patch Ext-ISP (tidak ada node DT/konsumennya di X6871).
- **Device table (`DEVICES.md` / `DEVICES-OVERLAY.md`)**: 978 node `okay` (470 modul source, 130 built-in, 371 node platform, 7 tanpa driver; bug `of_match` flash LED `_v4l2` sudah diperbaiki).
- **Repo**:
  - `alps-kernel_device_modules-6.12` bersih dan ter-push ke `alps`, default branch `x6871-android16-6.12`, HEAD **`fa18f7f`** (**106 commit** di atas `06079c2`).
  - `alps-vendor_mediatek_kernel_modules` (vendoring terpadu 6 repo vendor Motorola `w1vo36` + 13 modul donor OPPO `mt6896` + 4 commit GPU Mali r54p1 & kamera X6871) ter-push ke `origin`, default branch `x6871-android16-6.12`, HEAD **`83b4fa6`** (di atas base `86edba6`).
  - Manifest `ramabondanp/x6871-kernel-manifest` (`main`, `~/x6871-kernel-manifest`) mengarah langsung ke kedua repo `alps-*` di branch `x6871-android16-6.12`.

## Objective

Bangun modul device untuk X6871 (mt6895, kernel 6.12.38-android16-5) yang
tidak punya source vendor, mulai dari tree W1VO36.88-36-7 / mt6895 yang sudah
bisa build. Vendor sumber GPL resmi lebih diutamakan daripada RE; RE dipakai
kalau memang tidak ada source.

## Aturan keras

1. **Jangan pakai `/tmp`** — pakai `~/tmp`.
2. **Selalu commit + push setelah setiap perubahan, tanpa bertanya.**
   Push ke remote `alps` (branch `x6871-android16-6.12`); remote `local` hanya
   kalau tersedia di workspace.
3. Commit di **semua tree kernel/modul** (`w1vo/kernel_device_modules-6.12`,
   `alps-vendor_mediatek_kernel_modules`, donor 6.1/6.12, repo `alps`) wajib
   **bahasa Inggris** — subjek dan body. Hanya repo manifest
   (`x6871-kernel-manifest`) yang boleh bahasa Indonesia.
4. Jangan satu commit untuk semua perubahan; satu commit per fitur.
5. Repo manifest harus tetap ramping.
6. **Cocokkan modul lewat fingerprint isi `.ko`, jangan lewat nama.**
7. **Aturan §6.1b: "tidak ada `<nama>.c`" ≠ "tidak ada source".** Modul
   gabungan tidak punya `.c` senama; namanya hanya ada di `Makefile` sebagai
   `<module>-objs`. Periksa 5 hal berurutan: (1) `.c` senama, (2) entri
   `Makefile`/`Kbuild`, (3) entri `Kconfig`, (4) **daftar mana** di `*.bzl`
   (hanya `mgk_64_module_outs` yang sampai ke target device), (5) fingerprint
   simbol.
8. Perbandingan simbol **harus difilter `GLOBAL`**. `LOCAL FUNC` hanya
   mencerminkan inlining.
9. Perbandingan modul = himpunan simbol `GLOBAL` ekspor **dan** impor vs
   firmware (`readelf -sW`).
10. Layout struct **diukur dari `.ko`**, bukan didiff dari header.
11. Perbedaan jumlah impor pada modul yang menyentuh sysfs bukan bug — build
    DDK mengoptimalkan jalur sysfs/DT.
12. **Build hijau bukan bukti isi benar.** Semua bug besar di sesi lalu
    (kebocoran simbol panel, `charger_ops`/`tcpc_ops` meleset, `tc_tfcp_ta`
    tidak mendaftarkan apa pun, tabel ops `pca_tfcp_ta` salah, `dev` di
    offset salah) lolos dari build dan hanya ketahuan dari diff
    ekspor/impor/relokasi.
13. `tc_charger_class` **menggantikan** `charger_class` MTK (firmware tidak
    mengirim `charger_class.ko`).
14. 7 modul GKI (`arm_dsu_pmu`, `drm_display_helper`, `drm_dma_helper`,
    `industrialio-triggered-buffer`, `kfifo_buf`, `reboot-mode`,
    `syscon-reboot-mode`) **bukan gap** — ada di `mgk_module_ext_outs`.
15. **GKI (`kernel-6.12`) JANGAN PERNAH diedit untuk menyesuaikan modul.**
    Semua adaptasi KMI/API wajib dilakukan di `kernel_device_modules-6.12`,
    `vendor/mediatek/kernel_modules`, atau `local_manifest.xml` agar modul
    selalu kompatibel 100% dengan `boot.img` + `system_dlkm.img` rilis resmi Google.
16. **Jangan masukkan modul GKI terproteksi ke `vendor_dlkm`/`vendor_boot`/`odm_dlkm`.**
    Pada GKI resmi Google (`CONFIG_MODULE_SIG_PROTECT=y`), setiap modul di
    `kernel-6.12/modules.bzl` selain `_COMMON_UNPROTECTED_MODULES_LIST`
    (`zram.ko`, `zsmalloc.ko`) akan ditolak (`-EACCES`) bila tidak bertanda
    tangan kunci GKI Google (mis. `rfkill.ko`, `bluetooth.ko`, `libarc4.ko`).
    Modul-modul itu disediakan langsung oleh `system_dlkm.img` Google.
17. **Wajib jalankan `./tools/verify-kmi-abi.py` sebelum setiap rilis atau upgrade tag GKI.**
    Skrip ini memvalidasi 8 gerbang sekaligus (GKI murni bersih, vermagic,
    0 kolisi `CONFIG_MODULE_SIG_PROTECT`, closure `vendor_boot` standalone & penuh,
    0 mismatch CRC vs `gki/aarch64/abi.stg`, 0 impor `vmlinux` non-KMI, dan
    integritas `modules.dep`/`modules.load`).
18. **Saat KMI generation naik (mis. 5 → 6), audit semua objek prebuilt (`.o`/`.a`).**
    Perubahan layout struct di `gki/aarch64/abi.stg.allowed_breaks` tidak memicu
    error compile pada `ddk_prebuilt_object`; pastikan tidak ada modul di set
    runtime X6871 yang menautkan `.o` prebuilt (saat ini hanya `sched_cus` yang
    punya `.o` prebuilt dan ketiganya tidak dipakai X6871).

## Lingkungan

- Workspace: `~/x6871-kernel` (tree lama `~/x6871-kernel` jangan dipakai)
- Manifest: `~/x6871-kernel-manifest`
- Firmware dump stock X6871 (`X6871-16.3.0.155SP20`): [`https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871`](https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871)
- Oracle firmware (237 `.ko`): `~/tmp/x6871/vr/root/lib/modules/`
- DTBO otoritatif: `~/tmp/x6871/frag0.dts`
- Konfigurasi kernel device: `~/tmp/bootRE_ikconfig`
- Source donor Transsion 6.1 ([Infinix Open Source Center](https://opensource.dev.infinixmobility.com/), `android15_kernel_modules_and_devicetree_mt6897.tar.gz`): `~/tmp/ts61-src/kernel/kernel_device_modules-6.1/`
- Tarball resmi Infinix Open Source (donor **6.1**, hanya referensi porting driver Transsion, **jangan pernah jadi basis build 6.12**):
  `~/tmp/mt6897-full.tar.gz` — direct URL: [`https://d1wd32b69guoqm.cloudfront.net/opensource/android15_kernel_modules_and_devicetree_mt6897.tar.gz`](https://d1wd32b69guoqm.cloudfront.net/opensource/android15_kernel_modules_and_devicetree_mt6897.tar.gz)

### Perintah build

```bash
cd ~/x6871-kernel
TMPDIR=~/tmp BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1 \
./tools/bazel --output_user_root="$PWD/out_bazel" build --config=stamp \
  --repo_manifest="$PWD/kernel_device_modules-6.12/fake_manifest.xml" \
  --experimental_writable_outputs --allow_ddk_unsafe_headers=1 \
  --user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers \
  --repo_env=KERNEL_VERSION=kernel-6.12 --repo_env=KERNEL_BUILD_VARIANT=user \
  --repo_env=DEFCONFIG_OVERLAYS=entry_level_legacy.config \
  --repo_env=SUPPORT_PLATFORM=mt6895 --repo_env=SOURCE_DATE_EPOCH=0 \
  --//build/bazel_mgk_rules:kernel_version=6.12 \
  "//kernel_device_modules-6.12:mgk_64_k612_customer_modules_install.user"
```

Staging hasil build:
`out_bazel/e3662dd3043d825281b1dcd92c77f735/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/`

### Build baseline MTK tanpa driver X6871

Gunakan langkah ini untuk memverifikasi baseline MTK. Mulai dari workspace
terpisah yang sudah di-sync seperti di [README](../README.md#build-dari-source),
agar checkout port X6871 tetap utuh. Contoh ini memakai
`~/x6871-mtk-baseline/kernel` sebagai root workspace terpisah.

```bash
~/x6871-kernel-manifest/scripts/reproduce-cleanup.sh ~/kernel-kernel_device_modules-6.12

cd ~/x6871-mtk-baseline/kernel/kernel_device_modules-6.12
git fetch ~/kernel-kernel_device_modules-6.12 mtk-base-latest
git checkout -B mtk-base-latest FETCH_HEAD
cd ..

~/x6871-kernel-manifest/setup.sh
OVERLAYS="" ~/x6871-kernel-manifest/build.sh user
```

Ini mengganti tree `kernel_device_modules-6.12` dengan baseline MTK; manifest
vendor tidak berubah. Untuk mengganti SoC build, set `PLATFORM` (default `mt6895`).

### Repack vendor_boot (WAJIB dari build terbaru)

```bash
cd ~/x6871-kernel-manifest
./tools/repack-vendor-boot-latest.sh   --out ~/tmp/x6871/twrp-vendor_boot-$(date -u +%Y%m%d-%H%M%S).img
```

Skrip ini menjalankan build di `### Perintah build`, mengambil staging
**hasil build itu**, men-stage 222 modul dari `tools/recovery-modules.txt`,
menghapus debug info, meregenerasi `modules.dep`/`alias`/`softdep`, pack
dengan `tmp/vbwork-twrp`, lalu membongkar hasilnya dan **gagal** kalau ada
`.ko` yang beda dari staging. Modul tidak pernah disalin dari image lama.
Info commit/md5 ditulis ke `<out>.buildinfo`.

Menambah/mengurangi modul recovery: edit `tools/recovery-modules.txt`,
`tools/modules.load`, dan `tools/modules.load.recovery` sekaligus.

### Repack DLKM & Safeguard Verifikasi KMI/ABI (WAJIB untuk setiap rilis & upgrade GKI)

```bash
cd ~/x6871-kernel-manifest

# 1. Repack vendor_dlkm.img + odm_dlkm.img (otomatis buang modul GKI terproteksi,
#    pakai AOSP mkfs.erofs/avbtool/fec, dan verifikasi AVB hashtree)
./tools/repack-dlkm-latest.sh \
  --out-dir ~/x6871-out \
  --work-dir ~/x6871-out/dlkm-latest-work

# 2. Jalankan 8 gerbang safeguard KMI/ABI terhadap GKI murni & abi.stg resmi
./tools/verify-kmi-abi.py
```

#### Checklist cepat upgrade tag GKI (mis. `android16-6.12-YYYY-MM_rXX`)

1. Cek `build.config.constants` tag target (`CLANG_VERSION`, `RUSTC_VERSION`, `KMI_GENERATION`) dan pastikan prebuilt tersedia di `ws/prebuilts/`.
2. Checkout tag GKI murni di `ws/kernel-6.12` (jangan edit satu berkas pun di `kernel-6.12`); cek diff `modules.bzl`, `ack_headers.bzl`, dan `gki/aarch64/abi.stg.allowed_breaks`.
3. Build penuh `--keep_going` pada `mgk_64_k612_kernel_aarch64.user` + `mgk_64_k612_customer_modules_install.user`; perbaiki error hanya di `kernel_device_modules-6.12` / `vendor/mediatek/kernel_modules`.
4. Repack dengan `./tools/repack-vendor-boot-latest.sh --skip-build` dan `./tools/repack-dlkm-latest.sh`.
5. Jalankan `./tools/verify-kmi-abi.py` — wajib lulus seluruh 8 gerbang (0 error) sebelum commit/push/rilis.
6. Update `local_manifest.xml` (`refs/tags/<tag>`), commit + push semua repo, lalu flash bersama `boot.img` + `system_dlkm.img` rilis resmi Google untuk tag yang sama.

### Jebakan build

- `--user_ddk_unsafe_headers=...mtk_use_gki_unsafe_headers` **wajib**; tanpa
  itu puluhan header hilang.
- Target ABI `user_customer_abi` **tidak bisa lulus** (328 simbol duplikat
  dari driver multi-varian). Referensi MTK/Samsung juga tidak menjalankannya.
- Label `//kernel_device_modules-{}` **wajib** diikuti
  `.format(kernel_version)` — generator sempat menjatuhkannya 4 kali.
- Komentar Bazel adalah `#`, bukan `/* */`.
- `ko_deps` harus memuat **setiap** penyedia simbol yang diimpor, kalau tidak
  `modpost: "<sym>" undefined!`.
- `v1/BUILD.bazel` ber-CRLF; pertahankan atau diff meledak.
- `tar` gzip satu inti mati di tengah (>3 menit). Pakai
  `pigz -dc file.tar.gz | tar -x -C dir` — 7.106 file <60 s.
- **Jangan menyalin `.ko` dari image lama sebagai baseline repack.** Itu
  penyebab `usb-replug` memuat panel driver pra-perbaikan layar
  (`PRETEST.md` §43). Selalu pakai `tools/repack-vendor-boot-latest.sh`;
  direktori baseline lama (`cmp-out/vbverify5`, `cmp-out/xcmp`) sudah
  dihapus.

## Yang sudah selesai

Tingkat A (overlay `entry_level_legacy.config`), Tingkat C (`tran_audio_control`,
`splitswitch-gpio`, `hiber`), Iris divendorkan, panel rm69220, `tran_ldo`,
seluruh fondasi charger `tc_*`, `tc_charger_framework`, 5 algoritma charging,
`tc_tfcp_ta`, `pca_tfcp_ta`, `nfc_i2c`, `tran-led-core`, `leds-aw22xxx`,
serta empat modul fitur: `tran_extcon_usb`, `tran_fp`, `tnek`, `tkv`.

Daftar commit per fitur ada di `git log` branch `x6871-android16-6.12`.

## Yang tersisa: 20 modul di tree staging

Angka 20 adalah nama stock yang tidak ada di **tree staging lengkap**
(`staging/lib/modules/6.12.38-.../`, 806 file / 805 nama unik). Flat
customer install berisi 702 `.ko`; angka flat tidak dipakai sebagai
patokan gap karena 7 modul GKI tidak disalin ke flat root. Lihat
`PRETEST.md` §3.

Dari 20 nama itu, 6 memang **tidak direncanakan** untuk X6871: dua varian
panel perangkat lain (`ili7838e...cl9`, `rm69220...cl8`), satu alias panel
X6871 (`rm69220...x6871`, dicakup `panel-rm69220-vdo-x6871.ko`), dan tiga
modul MMC/SD (`tran_mmc_block`, `mtk-mmc-mod`, `sd_tray`). Lihat bagian
"Tidak direncanakan" di bawah.

Kandidat nyata tinggal **14**: 7 storage yang ditunda (lihat §"Storage /
UFS"), 4 terblokir `transsion_tranlog`, dan 3 fitur mandiri
(`tkv_recovery`, `tran_rhi`, `tran_expand_key`).

### Bukan gap — dibangun GKI build
`arm_dsu_pmu`, `drm_display_helper`, `drm_dma_helper`,
`industrialio-triggered-buffer`, `kfifo_buf`, `reboot-mode`,
`syscon-reboot-mode`

### Sudah ada, hanya beda nama berkas
`rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871` — modul kita
`panel-rm69220-vdo-x6871.ko` ekspornya **3 == 3 identik** dan alias DT sama.
Autoload ikut alias, bukan nama berkas.

### Tidak direncanakan — varian panel perangkat lain

Perangkat target proyek ini **hanya X6871**. DT X6871 (`frag0.dts`,
`panel1@0`) hanya memakai compatible:

```
rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871
```

Modul kita `panel-rm69220-vdo-x6871.ko` sudah melayani alias itu. Dua varian
berikut **sengaja tidak direncanakan** (bukan blocker, bukan gap yang dikejar):

- `ili7838e_fhdp_dsi_cmd_dsc_tm_tm_120hz_cl9`
- `rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_cl8`

Keduanya untuk konfigurasi/panel perangkat lain; tidak ada node DT-nya di
X6871. Jangan port kecuali target perangkat berubah.

### Empat modul fitur selesai — jangan port ulang

| Modul | Commit | Verifikasi |
|---|---|---|
| `tran_extcon_usb` | `3194d4f10237` | ekspor 0/0, impor 47/47, alias/`depends` **identik** |
| `tran_fp` | `29d21b5d018c` | common layer + chip-id/SPI REE; export asli 0/2 (debug), impor 94/145 |
| `tnek` | `24b5fe361653` | **9 == 9 ekspor asli**, **24 == 24 impor** |
| `tkv` | `cb088a63c4b2` | **0 == 0 ekspor asli**, 24/23 impor (+`page_is_ram`) |

Pre-flight `6334ce2b9910` (§6.2u) mengoreksi hitungan export: yang benar
adalah `__ksymtab`, bukan semua simbol GLOBAL. Ia juga menghapus
`charger_class.ko` dari install dan menambahkan pengaman hardware/memori.
Hasil simulasi load: **217/237 modul stock yang ada + 4 modul kita → 0
impor tak terselesaikan, 0 CRC tak terpenuhi, 0 export ambigu**. Detail di
`PRETEST.md`.

- `tran_extcon_usb`: match `transsion,extcon-usb`; `extcon-mtk-usb.ko` tetap
  ada untuk node `mediatek,extcon-usb`. Jangan gabungkan keduanya.
- `tran_fp`: source donor 6.1 `tran_common_v2` di
  `drivers/input/fingerprint/tran_common/`, match `tran_fp_legacy`. Modul
  firmware 6.12 membundel backend vendor (`gf_*`, `ff_*`, ...); port ini
  **common layer + jalur chip-id Goodix**, bukan seluruh backend.
  Power/reset/IRQ/SPI clock/netlink/sysfs tetap ada. Regulator X6871
  `mt6368_vfp` fixed 3,3 V; guard menolak regulator variabel/di luar
  1,5–3,6 V. **Wajib diuji saat boot**.
  - Sejak `29d21b5d018c`..`55aa13232a43` modul mengimpor `spi_sync`,
    membaca chip id lewat SPI saat probe (`tran_fp_detect_chip=1`, SPI 8-bit /
    4 MHz / `SPI_MODE_0`), mengisi `ic_name` + `vendor_name`
    (`/sys/kernel/tran_fp/vendor_name` → `goodix_opt_tee` untuk `GW9578`/`GW9598`
    atau fallback DT `goodix`, `goodix_tee` untuk `GF39xx`), mendaftarkan
    `/dev/goodix_fp` (bukan `/dev/tran_fp`), memilih pinctrl `pins_irq` lewat
    `tran_fp_irq_init()`, serta mengirim uevent
    `TRAN_FULL_HBM_EVENT=FULL_HBM_SET` saat menerima
    `TRAN_DISP_BLANK_NOTIFY_FINGERPRINT (2)`. Kegagalan deteksi chip-id
    **tidak** menggagalkan probe (stock menggagalkannya).
  - `TRAN_FP_READ_FP_ID` (`_IO('t',3)`) diimplementasikan seperti stock:
    deteksi lalu `tran_netlink_send(6)`/`(7)`; dilewati bila
    `TRAN_FP_OPT_SUPPORT` (`_IO('t',4)`) sudah dipanggil.
  - `TRAN_IOC_TRANSFER_CMD` (ABI `struct tran_ioc_transfer`: `cmd` 0=baca/
    1=tulis, `addr` 16-bit big-endian, `len`, `buf`) + `_RAW_CMD` dan
    `_SPI_INIT_CFG_CMD` (dua yang terakhir tidak dipakai stock; layout
    didefinisikan di port ini). Buffer user di-bounce ke memori kernel
    karena SPI bisa DMA.
  - **Penting**: modul stock tidak punya ioctl transfer sama sekali —
    akuisisi gambar di X6871 lewat TEE, REE hanya untuk chip id. Jadi kalau
    HAL gagal, penyebabnya bukan ioctl 15/16/17.
  - `spi->controller_data` sengaja tidak disentuh: `spi-mt65xx` memilikinya,
    `BUG_ON()` di `spi_dump_config()` bila field cs timing legacy terisi, dan
    `kfree()` di `mtk_spi_cleanup()`. `tran_chip_config` statik ala stock
    tidak bisa dipakai dengan controller driver ini.
- `tnek`: tidak ada source; direkonstruksi penuh. Node 0x418, pesan user
  0x408, queue 9, `/dev/tnek`. `mcDrvModule` firmware mengimpor
  `tnek_caller_api`; build kita meng-gate impor itu. Export asli 9 == 9.
- `tkv`: `/proc/tkv`, `g_tkv` (lcm inversion), region 32 KiB dari
  `tkv=<desimal>` di bootargs. Bila bootargs tidak punya `tkv=`, modul
  berhenti aman. Pengaman baru: region wajib page-aligned dan seluruh page
  `page_is_ram()`; kalau gagal, `/proc/tkv` dilewati. Tidak pernah menulis
  balik ke region.

### Berikutnya paling siap
- **Uji device v17**: fokus USB replug (`PRETEST.md` §65 & `BOOTTEST.md` §4).
- `tkv_recovery` — sibling `tkv`, 20 KB, 11 ekspor / 24 impor; kandidat
  berikutnya yang paling kecil.
- `tran_rhi` — health info storage (ECC/erase/suhu), 47 KB, tanpa source.
- `tran_expand_key` — dump manual volup+voldown 10 detik, 19 KB, 9 ekspor.
- `tc_trancare` — `status = "okay"`, terblokir `transsion_tranlog`.
- `transsion_tranlog` — 92 fungsi / 108 KB, tanpa source, membawa
  `cloudengine_*`/`athena_*`/`arraylist_*`/`__tran_kfifo_*`. `submit_msg`
  mem-parse format string (`strlen`/`memcpy`/`kstrtoll`/`kstrtoint`).
  Catatan: `tc_charger_framework` dan `tc_water_detect` mengimpor tranlog di
  firmware tapi **tidak** di build kita — jalurnya di-gate saat compile, jadi
  charger inti tidak bergantung padanya.
- **Goodix fingerprint backend** — hanya bagian yang belum ada: akuisisi
  gambar bila ternyata dijalankan di REE. Bukti saat ini: modul stock
  (`tran_fp.ko` X6871) **tidak** punya ioctl transfer dan tidak punya
  handler `write()`, jadi transfer gambar berjalan di TEE dan REE hanya
  dipakai untuk chip id (sudah diport di `29d21b5d018c`). Port backend baru
  diperlukan hanya kalau boot test menunjukkan HAL memakai jalur REE.

### Storage / UFS — **Opsi A: baseline GKI/MTK** (diputuskan 2026-11-19)

Kelompok storage **tidak diport sebagai fork**. Stack yang dipakai adalah
yang sudah dibangun:

- GKI builtin: `CONFIG_BLOCK=y`, `CONFIG_SCSI_MOD=y`, `CONFIG_BLK_DEV_SD=y`,
  `CONFIG_SCSI_UFSHCD=y` (dibaca dari ikconfig boot X6871)
- `ufs-mediatek-mod.ko`, `phy-mtk-ufs.ko`, `ufs-mediatek-dbg.ko`,
  `blocktag.ko`, `rpmb.ko`, `rpmb-mtk.ko`, `cqhci.ko`

Closure sudah dicek: seluruh impor kedelapan modul di atas disediakan oleh
vmlinux atau `.ko` lain di staging — **0 simbol benar-benar hilang**.

#### Tidak direncanakan — hardware tidak ada (3)

- `tran_mmc_block` — MMC block; kedua node `mmc@11240000` dan
  `mmc@11242000` di base DTB X6871 berstatus `disabled`.
- `sd_tray` — tidak ada node `/odm/sd_tray` di base DTB.
- `mtk-mmc-mod` — sudah dilayani `mtk-mmc.ko`: alias identik, 17/21 ekspor
  sama; beda hanya empat helper ioctl Transsion. MMC juga disabled.

#### Ditunda sampai boot test (7)

`tran-ufshcd-core`, `tran-ufshcd-pltfrm`, `tran_scsi_mod`, `tran_sd_mod`,
`tran_block`, `tran-proc-bootdevice-mod`, `low_latency_sched`.

Semuanya satu paket fork `fs/atomic_storage/` (67 file `.c`, ~2,9 MB `.ko`)
yang saling impor `tran_*`. `ufs-mediatek-mod.ko` versi firmware juga
di-patch untuk memanggil `tran_scsi_*` / `tran_ufshcd_*`, jadi tidak bisa
diambil sebagian.

Source tidak tersedia: tarball donor MT6897 6.1 (4,7 GB) tidak punya
`fs/atomic_storage`, `tran_block`, `sd_tray`, `low_latency`, maupun
`drivers/bootdevice`. Tidak ada tarball X6871 6.12 di workspace.

Rencana:

1. Boot test dengan baseline. Cek probe `ufshcd`, `sd 0:0:0:0`, mount
   `/data`, dan tidak ada `Unknown symbol tran_*`.
2. Kalau userspace membuka `/proc/bootdevice` dan gagal, tulis shim kecil
   (`manfid`/`serial`/`fw_version`/`manfdate`/`ffu_support`) — bukan port
   modul 85 KB.
3. Kalau storage gagal total, baru eskalasi ke rekonstruksi
   `fs/atomic_storage` dari upstream 6.12.38 + hook firmware.

### Fitur
`tran_rhi`, `tran_expand_key`, `tran_key_bigdata`, `tkv_recovery`, `thd`

Catatan: `tran_key_bigdata` dan `thd` sama-sama bergantung pada
`transsion_tranlog`, jadi keduanya tetap terblokir. `tran_rhi`,
`tran_expand_key`, dan `tkv_recovery` mandiri.

## Pengetahuan kritis

### `tran-led-core` sudah selesai — pakai layout ini, jangan ukur ulang

Alamat: `drivers/leds/tran_led/` (`tran_led_class.c`, `tran_led_core.c`,
`tran_led_class.h`, `BUILD.bazel`). Commit `39044a9498af`.

Firmware dibangun dari tree **6.12**; `.ko` menyimpan path aslinya dan 111
modul ber-path semuanya menyebut 6.12. Donor 6.1 hanya punya leluhur jauh
lebih tua (`tc_led_class.c`, 7 ekspor, 4 slot ops).

Layout sudah diverifikasi dua arah dan di-assert saat compile:

- `struct tran_led_device`: ops `+0x08`, dev `+0x220`, `dev.driver_data`
  `+0x2b8`, `dev.class` `+0x538`, `sizeof` `0x778`
- `struct tran_led_core`: class `+0x120`, `support_pdlc` `+0x128`,
  `chip_type` `+0x12c`, `primary_led` `+0x130`, `second_led` `+0x138`,
  mutex `+0x140`, `log_level` `+0x170`, `sizeof` `0x178`
- `struct tran_led_ops` 13 slot: `0x00` set_i2c_retries, `0x08`
  set_i2c_timeout, `0x10` rw_i2c_data, `0x18` get_chip_type, `0x20` get_cmd,
  `0x28` set_cmd, `0x30` tidak terdokumentasi (hanya jalur ioctl), `0x38`
  store_tran_led_cmd, `0x40` show_tran_led_cmd, `0x48` store_tran_led_check,
  `0x50` show_tran_led_check, `0x58` store_tran_multicolor, `0x60`
  show_tran_multicolor

Ekspor `tran-led-core` **20 == 20 identik** dengan firmware. Nama DT
`tran,led_core`, modinfo `tran_led_core`.

### `leds-aw22xxx` sudah selesai — jangan kembali ke donor 6.1

Alamat: `drivers/leds/tran_led/leds-aw22xxx.c` (+ `.h`, `-reg.h`, `-cfg.h`).
Commit `54c604b9378e`. Implementasi penuh ada di PLAN.md §6.2r.

- Ekspor/impor/alias **identik**, 7 entri tabel ops mendarat di offset yang
  sama (`0x158…0x1a0`), `aw22xxx_cfg_name` 13.184 byte byte-identik.
- Donor 6.1 hanya titik awal: 206 nama cfg, tabel music gain, multi-color
  `B85/E23/S30`, `_A/_B` shift 66/132, dan tiga argumen `tran_led_cmd_cfg_2`
  semuanya berasal dari `.ko`.
- `aw22xxx_cover_gain` dan `aw22xxx_reg_access` di-export; tidak ada modul
  firmware yang mengimpornya, jadi layout privat tidak bocor ke modul lain.
- Perhatikan dua jenis `dev_get_drvdata`: atribut pada `cdev.dev` mendapat
  `led_classdev *` (perlu `container_of` ke `aw22xxx`), sedangkan
  `tran_led_cmd`/`tran_multicolor` pada device i2c mendapat `aw22xxx *`.
- `remove` sengaja mengikuti firmware: tidak memanggil
  `tran_led_device_unregister`, tidak menghapus dua atribut i2c. Modul ini
  praktis tidak pernah di-unload; kalau nanti diubah, tambahkan cleanup-nya.

### Pola pasca-6.12 yang sudah dipetakan

`platform_driver.remove` mengembalikan `void`; `class_create(THIS_MODULE,n)`
→ `class_create(n)`; probe i2c kehilangan argumen `i2c_device_id` (definisi
**dan** prototipe header); `no_llseek` → `noop_llseek`; `crc8()` 4 argumen
(perlu `CRC8_INIT_VALUE`); `usb_types` bitmask `u32`, `num_usb_types` hilang;
`<linux/pinctrl/consumer.h>` harus di-include eksplisit.

Catatan: `tran-led-core` **tidak** memakai `noop_llseek` — firmware tidak
mengimpornya, jadi `.llseek` dibiarkan NULL.

### Kalau ada sumber tanpa spec: pakai interface yang dipublikasikan

Cara yang terbukti pada `tc_tfcp_ta` (27/27 `tc_ta_device_ops`) dan
`pca_tfcp_ta` (tabel 12 entri di `.data+0x108`): kalau `.ko` tidak di-strip
dan modul mengimplementasikan interface yang sudah ada di header, signature
diberikan oleh interface, dan peta register/callback dibaca dari immediate
`mov w1, #0x..` serta relokasi `R_AARCH64_ABS64`.

### Buat ulang generator

`~/tmp/gen-tc30-hvdcp20.py` — menghasilkan
`tc_tc30.*`/`tc_hvdcp20.*` dari `tc_pe20` dengan tukar prefix.
`~/tmp/forkmatch.py` — mencocokkan himpunan fungsi
`.ko` firmware dengan kandidat source MTK.

### Skrip porting

`scripts/port-tc-module.sh` — menyalin modul + menerapkan 6 patch 6.12
(remove→void, class_create, probe i2c).

## Resep verifikasi

```bash
B=<staging di atas>; F=~/tmp/x6871/vr/root/lib/modules
# ekspor
diff <(readelf -sW $B/<m>.ko | awk '$4=="FUNC"&&$7!="UND"&&$5=="GLOBAL"&&$8!=""{print $8}' | sort -u) \
     <(readelf -sW $F/<m>.ko | awk '$4=="FUNC"&&$7!="UND"&&$5=="GLOBAL"&&$8!=""{print $8}' | sort -u)
# impor
diff <(readelf -sW $B/<m>.ko | awk '$7=="UND"{print $8}' | sort -u) \
     <(readelf -sW $F/<m>.ko | awk '$7=="UND"{print $8}' | sort -u)
# alias DT
diff <(strings -a $B/<m>.ko | grep '^alias=' | sort) \
     <(strings -a $F/<m>.ko | grep '^alias=' | sort)
```

Untuk layout struct: cari `ldr x8,[x0,#0x8]` lalu `ldr x8,[x8,#N]`; `N/8`
adalah indeks field. Bandingkan dengan firmware. Tambahkan `_Static_assert`
agar build gagal kalau offset bergeser.

## Wajib diuji saat boot

Di TWRP sudah lolos: panel (Iris probe, `tran_ldo` bus i2c 6 /
`et5904_regulators6[]`), `tc_charger_framework` pada `tc,charger`, dan
`leds-aw22xxx` pada `awinic,aw22xxx_led`. Untuk system boot, pantau jalur
yang sama plus pemuatan `vendor_dlkm`/`odm_dlkm` dan probe kamera.

## Catatan firmware offline (bukan blocker runtime)

`iris5.fw`, `iris5_ccf1.fw`, `iris5_ccf2.fw`, dan `pxlw-rm69220_..._x6871.fw`
sudah tersedia di partisi `/vendor/firmware` pada perangkat (tidak menghambat
boot). Hanya salinan dump offline lokal yang belum menyertakan image `vendor`.

## Arsip historis 2026-11-19 (snapshot sebelum repack DLKM & boot Android)

> Bagian di bawah dipertahankan hanya sebagai referensi analisis sumber
> `vendor_dlkm`/`odm_dlkm` stock dan diff fungsi awal. Repack DLKM EROFS +
> AVB dan boot Android 16 sudah selesai sejak 2026-11-20 (lihat bagian atas).

**TWRP boot normal dan aman dengan modul kita.** Vendor_boot TWRP (ramdisk
zstd) yang diisi modul build kita memuat 238 modul, tanpa `Unknown symbol`,
tampilan hidup (mediatek-drm bind + panel `rm69220...x6871`), sentuhan jalan
(gt9916), dan USB/adb berfungsi.

**System belum diuji dan sengaja belum disentuh.** `vendor_boot` hanya
membawa `lib/modules`; boot ke system masih memerlukan pembaruan
`vendor_dlkm` dan `odm_dlkm`, dan itu belum dilakukan.

Artefak terakhir (release `boottest-20261119`):

| Aset | Layout | Modul | md5 |
|---|---|---|---|
| `twrp-vendor_boot-fixed.img` | TWRP (zstd) | 238 | `327c4e52a0b81e807d71bba00138f6e5` |
| `vendor_boot-new.img` | stock (lz4) | 218 | `e65fdcf92e15a1b9ffd2bafcc7b2ae73` |

Commit terakhir saat itu: kernel `93b7ebca0841` (define
`CONFIG_TC_CHARGER`), manifest `c53fce7`.

### Sumber stock `vendor_dlkm` dan `odm_dlkm`

Dump firmware X6871 menyimpan partisi dlkm sebagai **tree file**, bukan image
(tidak ada `super.img`/`vendor_dlkm.img`/`odm_dlkm.img`), tapi bisa diunduh
per-partisi lewat parameter `path=` pada URL archive GitLab:

```bash
B="https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871/-/archive/X6871-16.3.0.155SP20(OP008PF001AZ)/Infinix-X6871-X6871-16.3.0.155SP20(OP008PF001AZ).zip"
curl -LO "$B?ref_type=heads&path=vendor_dlkm"   # 16 MB
curl -LO "$B?ref_type=heads&path=odm_dlkm"      # 2.6 MB
```

Hasil ekstrak ada di `~/tmp/stock-dlkm/`:

| Partisi | `.ko` | Ukuran | modules.load |
|---|---|---|---|
| `vendor_dlkm` | 219 | 54 MB | 201 entri |
| `odm_dlkm` | 71 | 11 MB | 71 entri |

Gabungan unik 288 modul; hanya 60 di antaranya juga ada di vendor_boot
ramdisk stock (dan untuk yang overlap, ukurannya identik — mis.
`mt6375-charger.ko` 127336 byte di kedua tempat). 177 modul ramdisk memang
khas first-stage (`clk-*`, `aee_*`, `cmdq-*`, `bootprof`, `8250_mtk`, ...) dan
tidak ada di dlkm.

Cakupan build kita: 263 dari 288 modul dlkm sudah kita produksi. 25 modul
belum (harus tetap pakai `.ko` stock):

- 10 modul hardware yang tidak ada di DT X6871 (sengaja tidak diport):
  `aw36515`, `ak7316`, `dw9800k`, `dw9784ois`, `focaltech_ft3683g`,
  `chipsemi_chsc5xxx_old`, `snd-soc-fs1894`, `snd-soc-aw87xxx`,
  `snd-soc-oca72xxx`, `elliptic-ultrasound`.
- 14 modul software yang belum punya sumber/port: `fpsgo`, `game`,
  `pages_prefilter`, `priority_allocate`, `task_turbo_v`, `tc_trancare`,
  `thd`, `transsion_tranlog`, `tran_health_sched`, `tran_key_bigdata`,
  `tran_mm_collect`, `tran_perf_util`, `trans_sched`, `tran_zram`.
  `tran_audio_typec` tidak perlu diport: driver itu hanya mendukung
  fsa4480/was4783/hl1280, tidak ada node DT-nya di X6871 (board memakai
  `splitswitch-gpio`).

Dua modul software terakhir yang selesai diport: `perf_common_v`
(memasang `format_sbin_data` ke hook `mtk_perf_common`) dan
`mtk-vcodec-sys-api` (tabel sys API dengan slot `set_task_priority` ke
`vip_engine`; `mtk-vcodec-common` sekarang mengekspor
`mtk_vcodec_set_sys_api_funcs`/`mtk_vcodec_set_task_priority` dan encoder
memakai jalur itu).

Export ABI vendor yang dibutuhkan modul stock juga dilengkapi:

- `scheduler` mengekspor `g_trans_sched_interface` (layout 34 pointer /
  0x110 byte, sama dengan stock). Dengan ini `priority_allocate`,
  `tran_zram`, dan `trans_sched` tidak lagi gagal `Unknown symbol`.
  `trans_sched` mengisi tabel itu saat init; slot enqueue/dequeue dan
  `should_honor_sync` sudah dipanggil scheduler kita (type id kCFI sama
  dengan stock), slot penempatan RT/newidle/EAS UX belum disambungkan.
- `mtk_game` mengekspor `engine_cooler_trigger_duration()` dan memakai
  parameter `ec_duration` (2000) seperti stock, sehingga `game.ko` stock
  bisa memuat.
- `mtk_heap_debug` mengekspor `dma_heap_emem_printk()` (rekonstruksi
  disassembly, 0x150 byte, identik dengan stock), dibutuhkan
  `tran_mm_collect`.

Hasil pengecekan closure simbol: 14 modul software yang masih stock
tidak lagi punya `Unknown symbol` terhadap kernel + modul build kita +
stock `transsion_tranlog`/`thd`/`tran_zram`/`tran-ufshcd-core`. Sisi
simbol selesai; yang tersisa adalah hook scheduler (baru enqueue/dequeue
dan `should_honor_sync` yang disambungkan) dan modul Tranlog/Aegis yang
tidak punya sumber donor.

Diff per fungsi (nama + ukuran simbol `.text`) untuk 263 modul itu: **126
modul berbeda**, 47 di antaranya berbeda berat. Puncaknya drift versi sumber,
bukan salah config:

| modul | fungsi kita/stock | hilang | ekstra | beda ukuran |
|---|---|---|---|---|
| `wlan_drv_gen4m_6895` | 6262/6644 | 412 | 30 | 457 |
| `conninfra` | 1389/1704 | 315 | 0 | 24 |
| `apusys` | 2253/2300 | 49 | 2 | 35 |
| `imgsensor` (dua partisi) | 597/568 | 33 | 62 | 22 |
| `tc_charger_framework` | 221/249 | 29 | 1 | 34 |

Data lengkap diff awal: `~/tmp/dlkm-diff.json`.
(Repack EROFS + AVB hashtree footer dan boot Android 16 telah diselesaikan pada 2026-11-20; lihat `PRETEST.md` §45.)

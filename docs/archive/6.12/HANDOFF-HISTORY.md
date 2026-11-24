# Arsip Riwayat Rilis & Referensi Porting 6.12 (eks HANDOFF)

> **Arsip historis (read-only).** Dokumen ini menyimpan riwayat rilis `v1`–`v19-kmi6`,
> audit gap awal, pengetahuan modul fitur 6.12, dan snapshot 2026-11-19 yang sebelumnya
> berada di `docs/HANDOFF.md`.
>
> Untuk panduan build, konfigurasi, aturan keras, dan repack aktif, gunakan
> [BUILD.md](../../guides/BUILD.md) dan [FLASH-AND-TEST.md](../../guides/FLASH-AND-TEST.md).

## Status Rilis Terbaru & Ringkasan Riwayat (2026-11-22)

### Rilis terbaru: `gki-kmi6-20261122` (GKI `android16-6.12-2026-09_r16`, kernel `20a8f5d`, `vendor_boot` v19-kmi6)

```text
x6871-twrp-vendor_boot-v19-kmi6.img  md5 91eb249ff001d250fad855c40476f1b5  67.108.864 B
vendor_dlkm.img                      md5 5f7b6cecb1c44a1ffc3280dd481fbfcf  24.551.424 B
odm_dlkm.img                         md5 6ee3cadceb5c4750dbbfe3d0056b6ea8   4.206.592 B
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
```

Digantikan oleh v18 (`32a8db7`, di-squash dari `6230061`+`f661c15`) karena `usb_gadget_connect()` terbukti no-op dan non-stock (`PRETEST.md` §65–§67).

### Rilis sebelumnya: `rcv-usb-20261122` (kernel `68db913`, `vendor_boot` v16 + DLKM v15)

```text
x6871-twrp-vendor_boot-v16.img  md5 eda8e578cb2e52c8718fe085271654cd  67.108.864 B
vendor_dlkm.img                 md5 72daa1f10eba75d9cd0e3359a27ff76f  24.551.424 B
odm_dlkm.img                    md5 99b2194fa63cab8c751f71b8fbd4eb5e   4.206.592 B
```

Perbaikan v16 / DLKM v15 (`PRETEST.md` §64):
1. **Earpiece (`mt6895-mt6368.ko`, `22efa7e` + `aca5276`)**: samakan enum `RCV Mux`, rute DAPM `Playback_R_DAC` (`RCV Select` + `Headset_PGAL/R_DAC`), serta handler event `mt_rcv_event` dengan `mt6895-mt6368.ko` stock.
2. **USB replug (`mtu3.ko` + `tran_extcon_usb.ko`, `68db913`)**: antrekan role switch di `extcon_wq`, samakan urutan `mtu3_dev_on_off()` / `ssusb_mode_sw_work_v2()` (tanpa `ssusb_phy_dp_pullup()` prematur saat probe/disconnect), dan jaga `softconnect` di `mtu3_gadget_pullup()`.

Hasil uji v14 (`dmesg8.txt`/`logcat6.txt`): **charging HVDCP20/PD LULUS, tidak ada panic**. Dua bug sisa diperbaiki (`PRETEST.md` §64):
1. **Earpiece (suara telepon tidak keluar di speaker atas)**: `mt6895-mt6368.ko` stock memakai nilai enum `RCV Select=Playback_R_DAC` (`1` pada 2-item enum) alih-alih `RCV Mux`, serta memakai `mt_rcv_event` & jalur PGA speaker L/R.
2. **USB cabut-colok (`mtu3_gadget_pullup`)**: saat colok kedua (`new device session without pullup (gadget bound=0)`), `adbd` belum merebind gadget atau `mtu3_dev_on_off` / `ssusb_mode_sw_work_v2` tidak cocok urutan stock.

### Rilis sebelumnya: `iommu-chg-earpiece-usb-20261122` (kernel `5f569d0`, `vendor_boot` v14 + DLKM v13)

```text
x6871-twrp-vendor_boot-v14.img  md5 b6a1ee7cd90aa34d9299f18fb50504e9  67.108.864 B
vendor_dlkm.img                 md5 c7f74c5bd25df83b55989fb6ef8bd3ef  24.551.424 B
odm_dlkm.img                    md5 99b2194fa63cab8c751f71b8fbd4eb5e   4.206.592 B
```

Perbaikan tambahan v14 (`PRETEST.md` §63, dari `pstore2.txt`):
- **Boot race panic `mtk_iommu.ko` (`5f569d0`)**: inisialisasi `INIT_LIST_HEAD(&data->hw_list)` dipindah ke sebelum `iommu_device_register()` (karena `of_iommu` bisa memanggil `mtk_iommu_probe_device` saat registrasi sebelum `list_add_tail` selesai) dan tambah guard NULL `larbdev` pada jalur fault/dump `mtk_iommu`.

### Rilis sebelumnya: `chg-earpiece-usb-20261122` (kernel `8944601`, `vendor_boot` v13 + DLKM)

```text
x6871-twrp-vendor_boot-v13.img  md5 d0a81b920454db3347aa16aa786416d9  67.108.864 B
vendor_dlkm.img                 md5 c7f74c5bd25df83b55989fb6ef8bd3ef  24.551.424 B
odm_dlkm.img                    md5 99b2194fa63cab8c751f71b8fbd4eb5e   4.206.592 B
```

Hasil uji v12 (`dmesg7.txt`/`logcat5.txt`/`pstore1.txt`): **screen-off FOD, DT2W, dan flashlight LULUS**. 3 bug baru diperbaiki di v13 (`PRETEST.md` §62):
1. **Panic saat charging dengan adapter (`tc_charger_framework.ko`, `0af45b1`)**: `alg_id_enum` / `alg_name_array[]` di `tc_charger.h` hanya berisi 4 entri (`none`, `pe5`, `pd`, `pe20`) tanpa `tc30`/`hvdcp20`, sehingga `tchg_alg_id("hvdcp20")` mengembalikan `-22` dan `Pump_Express_show` mengindeks `alg_name_array[-22]` (UBSAN panic di `pstore1.txt`). Samakan 6 entri stock (`none`, `pe5`, `tc30`, `pd`, `hvdcp20`, `pe20`), tambah switch `TC30_ID`/`HVDCP20_ID`, dan beri bounds check `tchg_alg_id_to_name()`.
2. **Earpiece speaker (`mt6895-mt6368.ko`)**: perbaiki pemilihan routing `RCV Mux` vs `Headset_PGAL/R` untuk earpiece di `mt6895-mt6368.c`.
3. **USB cabut-colok (`tran_extcon_usb.ko` + `mtu3.ko`, `8944601`)**: `mt6375_get_vbus_gd_stat` fallback & `extcon_wq` di `tran_extcon_usb` + `mtu3_gadget_pullup` sinkron dengan status gadget saat cabut-colok kabel.

### Rilis sebelumnya: `sofod-dt2w-flash-20261122` (kernel `ebca3e1`, `vendor_boot` v12 + DLKM)

```text
x6871-twrp-vendor_boot-v12.img  md5 91e4f93e9c84805c83cb576b9840cb2b  67.108.864 B
vendor_dlkm.img                 md5 cf905997d112d846c4fc947cf125368a  24.551.424 B
odm_dlkm.img                    md5 99b2194fa63cab8c751f71b8fbd4eb5e   4.206.592 B
```

Hasil uji v11 (`dmesg6.txt`/`logcat4.txt`): **FOD saat AOD LULUS** (layar tidak lagi rusak). Sisa 3 bug diperbaiki di v12 (`PRETEST.md` §61):
1. **Screen-off FOD (`panel-rm69220-vdo-x6871.ko`, `0d456ba`)**: `panel_extcon_poweroff()` mematikan regulator `vddi-gpios` saat layar mati sehingga sensor optik FOD di bawah panel ikut kehilangan power. Pertahankan `vddi-gpios` HIGH saat panel power-off (sesuai stock).
2. **DT2W (`gt9916_common.ko`, `e4ed999`)**: `/proc/gesture_coord` memakai `simple_read_from_buffer()` (mengembalikan 1 byte bukan 0 pada offset > 0) dan `gesture_write()` memakai `"al2"` untuk mengaktifkan sensor tanpa mematikan mask `0xcc` (DT2W).
3. **Flashlight (`flashlight.ko` + `flash_sgm37864` + `ocp81375`, `ebca3e1`)**: nonaktifkan makro `PT`/`PT_STRICT` (low-battery/thermal power throttling) di `flashlight-core.h` yang tidak dipakai stock agar senter bisa menyala normal.

### Rilis sebelumnya: `aod-dt2w-flash-20261122` (kernel `78a1441`, `vendor_boot` v11 + DLKM)

```text
x6871-twrp-vendor_boot-v11.img  md5 fb6d3b0b817c92e2bf9d2952fa938b0a  67.108.864 B
vendor_dlkm.img                 md5 b62326f37fb65a44d7e0c2b43bf2e2f7  24.551.424 B
odm_dlkm.img                    md5 b43c414db6b394814c3fe2025c0ff745   4.206.592 B
```

Hasil uji v10 (`dmesg5.txt`/`logcat3.txt`): rekam video & optical FOD normal **LULUS**. Sisa 3 bug diperbaiki di v11 (`PRETEST.md` §60):
1. **FOD saat AOD merusak layar (`panel-rm69220-vdo-x6871.ko`, `4c2d079` + `1495bb4`)**: hapus perintah `0x39`/`0x38` idle mode pada `panel_doze_enable/disable` dan samakan tabel HBM alpha RM69220 dengan stock.
2. **DT2W tidak merespons (`gt9916_common.ko`, `d993e86` + `78a1441`)**: perbaiki `/proc/gesture_coord` dan `gesture_maps` Goodix (`0xcc` → `0xcc`/`1`).
3. **Flashlight senter mati (`flash_sgm37864` + `ocp81375`)**: tambah subdev V4L2 flashlight dan sinkronkan `flashlight-core.c` untuk X6871.

### Rilis sebelumnya: `venc-fod-dt2w-20261122` (kernel `17a6b66d7927`, `vendor_boot` v10 + DLKM)

```text
x6871-twrp-vendor_boot-v10.img  md5 ce93e06963097254e348905671316371  67.108.864 B
vendor_dlkm.img                 md5 f285d1a7e07f64f161be9e62f3e6bb2b  24.551.424 B
odm_dlkm.img                    md5 f4e2ff7b74eeff73cdbd1bb8bd0d4aa9   4.206.592 B
```

Boot pembanding `normal2.txt` (GKI `Image` kita + modul stock) berhasil merekam video 1080p, DT2W saat AOD, dan optical FOD — mengisolasi 3 masalah tersisa ke **modul kita sendiri** (`PRETEST.md` §59):
1. **Rekam video / VENC (`mtk-vcodec-enc.ko`, `17a6b66d7927`)**: `normal2.txt` mencetak `check_codec_id ipi id 1 is correct` saat init VENC, sedangkan `dmesg3`/`dmesg4` tidak pernah mencetaknya. Di `mtk_vcodec_drv.h`, `VENC_H264..VENC_H263` menyambung enum setelah `VDEC_AV1 (12)` sehingga `VENC_H264 == 13` alih-alih `1`. `check_codec_id()` diam-diam membalas `status=-1`, membuat VCP tidak mengalokasikan buffer ref/rec/comv HW (`0x74..0x88 == 0` → fault `LARB7_PORT24`/`PORT3 mva=0x0` → VCP WDT). Fix: reset `VENC_H264 = 1`, perluas `struct mtk_codec_capability` ke 24 B + kontrol `ADAB_CAPABILITY` 4x `U32`, jalankan `slbc_request()` walau `slbc_register_activate_ops` gagal, cek `msg->status != 0` pada `VCU_IPIMSG_ENC_SET_PARAM_DONE`, dan guard NULL `inst`/`vsi` di `mtk_venc_dvfs_sync_vsi_data`.
2. **DT2W saat AOD (`mediatek_drm_v1.ko` + `adaptive-ts.ko`)**: samakan ABI notifier enum AOD (`AOD_NOTIFY=3`, `TRAN_AOD_ON=0`/`TRAN_AOD_OFF=1`) dan kirim `TRAN_DISP_BLANK_NOTIFY_EARLY_AOD_ON (3)` pada `panel_doze_enable()` serta cegah `tp_resume` membabi-buta.
3. **Optical FOD (`mediatek_drm_v1.ko` + `gt9916_common.ko`)**:
   - `mediatek_drm_v1`: kirim `TRAN_DISP_BLANK_NOTIFY_FINGERPRINT (2)` di akhir `mtk_drm_crtc_set_panel_hbm(crtc, true)`.
   - `gt9916_common`: `/proc/fingerprint_status` menulis perintah Goodix `0x30` (`len=5`, `data[0]=0`/`1`), `brl_gesture()` zero-init `cmd`, `brl_event_handler()` mendeteksi FOD down (`0x88`) / up (`(pre_buf[0] & 0xf) == 0`) dengan key `195` (`0xc3`), dan `goodix_ts_resume()` membersihkan `g_fp_flag`.

### Hasil uji perangkat sebelum migrasi (KMI 5)

- **Boot & recovery**: TWRP + Android 16 boot sampai launcher dengan **222** modul `vendor_boot` (`modules.load` 165, `modules.load.recovery` 216) + **269** modul DLKM (**212** `vendor_dlkm` + **57** `odm_dlkm`, `modules.load` 194/57), 100% source, closure simbol **0 unresolved** (hanya weak `mtk_drm_gateic_set_backlight`).
- **Layar & AOD**: `panel-rm69220-vdo-x6871.ko` (4 mode 144/120/60/40 Hz byte-identik stock, 8bpc/1056 Mbps, 0 underrun) + `mediatek_drm_v1.ko` (C3D dual-pipe SRAM + `PQ_VIRTUAL_SET_PROPERTY` 12 B + AOD).
- **GPU & SCP**: Mali r54p1-11eac0 donor OPPO + fix layout `gpufreq_shared_status` + `SCP_IPI_COUNT=59`.
- **USB**: uji cabut-colok sempat lulus (`PRETEST.md` §42.1), lalu gagal di Android v16. Pada uji balik v18, masalah tetap terjadi dengan modul stock dan GKI kustom yang sama (`PRETEST.md` §67). Belum ada hasil uji cabut-colok pada KMI 6 di log.
- **Charger & audio**: fast charging HVDCP20/PD lulus, spam IRQ battery OC 65 Hz ditutup, earpiece dan speaker FS1599 berfungsi. Haptic, Wi-Fi, UFS, touch, DT2W, dan sidik jari dalam layar juga lulus pada build KMI 5.
- **Kamera**: foto, rekam video 1080p, dan senter lulus (`PRETEST.md` §59–§62).

### Komposisi modul & repack

- **Set `vendor_boot` (222 modul)**: 20 nama stock tidak ada di build (6 tidak direncanakan: panel `cl8`/`ili7838e`, alias panel X6871, 3 MMC/SD; 14 kandidat: 7 storage Transsion, 4 terblokir `transsion_tranlog`, 3 fitur mandiri). Lima modul build-only ditambahkan: `adaptive-ts`, `gt9916_common`, `mtk-mmc`, `panel-rm69220-vdo-x6871`, `tran_richtap_haptic_hv`.
- **Set DLKM KMI 6 (266 modul)**: `vendor_dlkm` (209) dan `odm_dlkm` (57) memakai EROFS + AVB hashtree footer dan di-flash via fastbootd. Dibanding set KMI 5 (269 modul), `rfkill`, `bluetooth`, dan `libarc4` kini disediakan oleh `system_dlkm.img` resmi Google, bukan `vendor_dlkm`.
- **Repack `vendor_boot`**: selalu pakai `tools/repack-vendor-boot-latest.sh` (lihat [BUILD.md](../../guides/BUILD.md#repack-vendor_boot-wajib-dari-build-terbaru)). Jangan menyalin `.ko` dari image lama atau memakai `tools/pack-vendor-boot.sh` legacy (`PRETEST.md` §43/§44).

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

Ikuti [FLASH-AND-TEST.md](../../guides/FLASH-AND-TEST.md) §2–§4 untuk setiap pembaruan GKI atau modul:

1. **Verifikasi KMI/ABI sebelum flash**: jalankan verifier sesuai [FLASH-AND-TEST §2](../../guides/FLASH-AND-TEST.md#2-membuat-image-vendor_boot--dlkm) (wajib lulus seluruh 8 gerbang).
2. **Flash pasangan GKI KMI 6 yang serasi**: `x6871-twrp-vendor_boot-v19-kmi6.img` + `vendor_dlkm.img` + `odm_dlkm.img` wajib dipasangkan dengan `boot-lz4.img` + `system_dlkm.erofs.img` GKI resmi Google `android16-6.12-2026-09_r16`.
3. **Checklist regresi subsistem**: TWRP, layar 144/120/60/40 Hz & AOD, FOD (layar menyala, AOD, screen-off), DT2W, kamera foto & rekam video 1080p, flashlight, audio speaker & earpiece, Wi-Fi/BT, USB cabut-colok (ADB dan MTP), dan fast charging HVDCP20/PD.

### Catatan kamera, device table & repo

- **Kamera (`PRETEST.md` §26, §51, §53)**: 4 sensor kamera X6871 (`s5khm6sx`, `gc32e1`, `gc02m3`, `gc02m3macro`) + `camera_eeprom_v4l2` sudah diport (`75ca1ac4a1ae`, `scripts/add-camera-x6871.sh`) dan kamera foto + rekam video sudah berjalan pada uji terdahulu. Build KMI 7 kemudian menambahkan port OTP baca-saja untuk S5KHM6SX dan GC32E1 (`1d259ab`). [Uji kamera KMI 7](PRETEST.md#69-uji-kamera-dengan-port-otp--kmi-7) dilaporkan normal, tetapi penggunaan data OTP oleh HAL belum terverifikasi. Ext-ISP tidak diport karena tidak ditemukan node DT atau konsumen stock di X6871.
- **Device table ([`DEVICES.md`](../../hardware/DEVICES.md) / [`DEVICES-OVERLAY.md`](../../hardware/DEVICES-OVERLAY.md))**: 978 node `okay` (470 modul source, 130 built-in, 371 node platform, 7 tanpa driver; bug `of_match` flash LED `_v4l2` sudah diperbaiki).
- **Repo**:
  - `alps-kernel_device_modules-6.12`: branch `x6871-android16-6.12` memuat refaktor konfigurasi di `0fba8e7`. Image rilis `gki-kmi6-20261122` memakai `fa18f7f`.
  - `alps-vendor_mediatek_kernel_modules` (vendoring terpadu 6 repo vendor Motorola `w1vo36` + 13 modul donor OPPO `mt6896` + 4 commit GPU Mali r54p1 & kamera X6871) ter-push ke `origin`, default branch `x6871-android16-6.12`, HEAD **`83b4fa6`** (di atas base `86edba6`).
  - Manifest `ramabondanp/x6871-kernel-manifest` (`main`, `~/x6871-kernel-manifest`) mengarah langsung ke kedua repo `alps-*` di branch `x6871-android16-6.12`.

## Yang sudah selesai

Tingkat A (overlay `entry_level_legacy.config`), Tingkat C (`tran_audio_control`,
`splitswitch-gpio`, `hiber`), Iris divendorkan, panel rm69220, `tran_ldo`,
seluruh fondasi charger `tc_*`, `tc_charger_framework`, 5 algoritma charging,
`tc_tfcp_ta`, `pca_tfcp_ta`, `nfc_i2c`, `tran-led-core`, `leds-aw22xxx`,
serta empat modul fitur: `tran_extcon_usb`, `tran_fp`, `tnek`, `tkv`.

Daftar commit per fitur ada di `git log` branch `x6871-android16-6.12`.

## Audit historis: 20 nama modul stock tidak ada di staging KMI 5

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
- **Uji regresi pada GKI resmi KMI 6**: ulangi checklist [`FLASH-AND-TEST.md` §4](../../guides/FLASH-AND-TEST.md#4-checklist-boot-per-subsistem), termasuk USB cabut-colok.
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

### `leds-aw22xxx` — port 6.12 dan status probe

Alamat: `drivers/leds/tran_led/leds-aw22xxx.c` (+ `.h`, `-reg.h`, `-cfg.h`).
Commit `54c604b9378e`. Implementasi penuh ada di [PLAN.md §6.2r](PLAN.md).
Pada build uji KMI 7, `47d7517` memperbaiki arah GPIO interrupt.
Probe dilaporkan berhasil; [uji efek LED masih pending](PRETEST.md#71-uji-probe-aw22xxx--kmi-7).

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

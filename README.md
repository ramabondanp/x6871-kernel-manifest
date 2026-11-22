# Manifest Kernel 6.12 — Infinix GT 20 Pro (X6871 / MT6895)

Workspace Bazel+Kleaf untuk membangun modul kernel **Android 16 / kernel 6.12 / MediaTek MT6895** untuk **Infinix GT 20 Pro (X6871)** (berbasis donor MTK 6.12 Motorola `w1vo36.88-36-7` + OPPO `mt6896`).

- **Device modules (`kernel_device_modules-6.12`)**: [`alps-kernel_device_modules-6.12`](https://github.com/ramabondanp/alps-kernel_device_modules-6.12/tree/x6871-android16-6.12) (`x6871-android16-6.12`, **103 commit** di atas baseline `06079c2`, HEAD `6230061`)
- **Vendor MTK modules (`vendor/mediatek/kernel_modules`)**: [`alps-vendor_mediatek_kernel_modules`](https://github.com/ramabondanp/alps-vendor_mediatek_kernel_modules/tree/x6871-android16-6.12) (`x6871-android16-6.12`, **4 commit** X6871 di atas base Motorola + 13 donor OPPO `86edba6`, HEAD `83b4fa6`)
- **Output build X6871**: staging **806 file** (**805** nama unik), flat customer install **702** `.ko`
- **Output baseline MTK murni** (`mtk-base-latest`): **1.401** `.ko`
- **Panduan cepat dokumen**:
  - [`docs/HANDOFF.md`](docs/HANDOFF.md) — ringkasan status terkini, aturan kerja, perintah build/repack, dan pengetahuan kritis
  - [`docs/BOOTTEST.md`](docs/BOOTTEST.md) — prosedur flash, rollback, dan checklist uji boot per subsistem
  - [`docs/PRETEST.md`](docs/PRETEST.md) — log teknis kronologis (§1–§65) hasil audit statis, RE biner, dan uji device
  - [`docs/PLAN.md`](docs/PLAN.md) — rencana porting awal dan bukti investigasi per modul (§6.x)
  - [`docs/DEVICES.md`](docs/DEVICES.md) / [`docs/DEVICES-OVERLAY.md`](docs/DEVICES-OVERLAY.md) — tabel pemetaan node Device Tree X6871 ke driver

---

## Quickstart

### A. Build port Infinix X6871 (disarankan)

`local_manifest.xml` langsung mengarah ke branch `x6871-android16-6.12` pada `alps-kernel_device_modules-6.12` dan `alps-vendor_mediatek_kernel_modules`, yang sudah memuat seluruh driver X6871 (panel RM69220, Pixelworks Iris, `tran_ldo`, stack charger Transsion, audio FS1599, 4 sensor kamera + EEPROM, flashlight, haptic, touch Goodix GT9916, optical fingerprint `tran_fp`, Mali r54p1-11eac0, dan fix VENC/GPU/SCP).

```bash
git clone https://github.com/ramabondanp/x6871-kernel-manifest ~/x6871-kernel-manifest

# 1. Sync workspace AOSP + overlay manifest X6871
mkdir -p ~/x6871-kernel && cd ~/x6871-kernel
repo init -u https://android.googlesource.com/kernel/manifest \
          -b common-android16-6.12-2025-09
cp ~/x6871-kernel-manifest/local_manifest.xml .repo/local_manifests/x6871.xml
repo sync -j16

# 2. Siapkan workspace, lalu build (default OVERLAYS=entry_level_legacy.config untuk X6871)
~/x6871-kernel-manifest/setup.sh
~/x6871-kernel-manifest/build.sh user
```

Hasil build berada di:
`out_bazel/*/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/`

### B. Build baseline MTK murni (tanpa driver X6871)

Gunakan langkah ini bila hanya ingin memverifikasi tree MTK bersih tanpa kode Motorola maupun Transsion:

```bash
cd ~/x6871-kernel-manifest
./scripts/reproduce-cleanup.sh ~/kernel-kernel_device_modules-6.12

cd ~/x6871-kernel/kernel_device_modules-6.12
git remote add local ~/kernel-kernel_device_modules-6.12
git fetch local mtk-base-latest
git checkout -B mtk-base-latest FETCH_HEAD
cd ..

~/x6871-kernel-manifest/setup.sh
OVERLAYS="" ~/x6871-kernel-manifest/build.sh user
```

Untuk SoC lain: `PLATFORM=mt6991 ~/x6871-kernel-manifest/build.sh user` (default: `mt6895`).

> **Catatan branch**: `x6871-android16-6.12` di `alps-kernel_device_modules-6.12` dibangun di atas baseline `06079c2` (keturunan langsung `android16` `30a0466a`) agar riwayat `android16` tetap bersih. Daftar lengkap commit: `git log --oneline 06079c2..HEAD`.

---

## Status Runtime & Rilis Terbaru (2026-11-22)

Seluruh partisi modul (**222** modul `vendor_boot` + **212** `vendor_dlkm` + **57** `odm_dlkm`) dibangun **100% dari source**.

### Status per subsistem

| Subsistem | Status | Catatan |
|---|---|---|
| Boot Android 16 & TWRP | ✅ Terbukti | Boot sampai launcher, 0 unresolved symbol |
| Layar RM69220 (144/120/60/40 Hz) & AOD | ✅ Terbukti | C3D dual-pipe + PQ ABI fixed, 0 underrun |
| GPU Mali r54p1-11eac0 & gpufreq | ✅ Terbukti | Donor OPPO + fix layout `gpufreq_shared_status` |
| Audio bottom speaker (MT6368 + FS1599 PA) | ✅ Terbukti | Kontrol `tran_audio_control` + PA switch aktif |
| Wi-Fi, Haptic, Touch normal | ✅ Terbukti | Tidak ada spam IRQ battery OC |
| Kamera foto & rekam video (save) | ✅ Terbukti | 4 sensor + EEPROM + VENC H264/ADAB/SLBC (`17a6b66d7927`) |
| Optical FOD (layar menyala, AOD, screen-off) | ✅ Terbukti | `/dev/goodix_fp` + HBM uevent + `vddi-gpios` HIGH (`59ed7e7`, `0d456ba`) |
| DT2W & Flashlight / Torch | ✅ Terbukti | Fix `al2` (`e4ed999`) + `#undef` PT throttling (`ebca3e1`) |
| **Fast Charging (HVDCP20/TC30 adapter)** | ✅ Terbukti (`v14`) | `tc30`/`hvdcp20` di `alg_name_array` + guard bounds check (`0af45b1`); uji v14 tanpa panic |
| **Earpiece speaker (`RCV Mux`)** | ✅ Lulus (`v16`) | Restore `RCV Select=Playback_R_DAC` (`aca5276`); terkonfirmasi di `dmesg9.txt` (`mt_rcv_event`, mux 1) |
| **USB replug berulang** | 🔄 Menunggu uji bersih (`v18`) | Revert `6230061` (no-op) + samakan `mtu3.ko` dengan stock X6871 (`f661c15`); uji tanpa `stop/start adbd` |

### Rilis uji terbaru: `mtu3-stock-20261122` (kernel `f661c15`)

```text
x6871-twrp-vendor_boot-v18.img  md5 73b94a9f88ed39a852e8a1343978d37e  67.108.864 B
vendor_dlkm.img                 md5 72daa1f10eba75d9cd0e3359a27ff76f  24.551.424 B
odm_dlkm.img                    md5 99b2194fa63cab8c751f71b8fbd4eb5e   4.206.592 B
```

Jika sudah memakai v16, cukup flash `vendor_boot` v18; kedua DLKM identik.

### Ringkasan perjalanan rilis

| Rilis | `vendor_boot` | Sorotan utama |
|---|---|---|
| `mtu3-stock-20261122` | v18 | Revert `6230061` (no-op non-stock) + samakan `mtu3.ko` dengan stock (`mdelay(4)`, `ssusb_phy_dp_pullup`, hapus `cdp-block` di `ssusb_gadget_init`); menunggu uji bersih |
| `mtu3-replug-20261122` | v17 | (Direvert di v18) `usb_gadget_connect()` pada NONE → DEVICE |
| `rcv-usb-20261122` | v16 | Fix earpiece `Playback_R_DAC` (enum/route/event stock) + pullup UDC saat replug (workqueue/urutan role switch stock) |
| `iommu-chg-earpiece-usb-20261122` | v14 | Fix boot race panic `mtk_iommu` (`hw_list` sebelum `iommu_device_register` + NULL guard `larbdev`) di atas v13 |
| `chg-earpiece-usb-20261122` | v13 | Fix panic charging HVDCP20 (`tc30`/`hvdcp20` `alg_name_array`), earpiece speaker (`RCV Mux`), USB replug (`mt6375_get_vbus_gd_stat` + `extcon_wq`) |
| `sofod-dt2w-flash-20261122` | v12 | Fix screen-off FOD (`vddi-gpios` tetap HIGH), DT2W (`al2` tidak mematikan `0xcc`), dan flashlight PT throttling sesuai stock |
| `aod-dt2w-flash-20261122` | v11 | Fix FOD di AOD (hapus `0x39` idle mode + alpha stock), DT2W 1-byte read + `gesture_maps`, V4L2 flashlight (`flash_sgm37864` + `ocp81375`) |
| `venc-fod-dt2w-20261122` | v10 | Fix akar masalah VENC (`VENC_H264=1`), ABI notifier AOD/HBM, DT2W AOD, `/dev/goodix_fp` + FOD key `195` |
| `video-touch-20261121` | v9 | Wake awal IRQ gestur, log diagnostik VSI VENC & `tran_fp` |
| `touchfix-20261121` | v8 | Kembalikan gate `suspended` di `gsx_gesture_ist` + bersihkan event gestur |
| `qpabi-fpgest-20261121` | v7 | Perbaiki 6 field QP per-frame VENC + fallback `goodix_opt_tee` |
| `vid-fl-dt2w5-20261121` | v6 | C3D SRAM guard, flashlight `ocp81375_v4l2`, DT2W key `198` |
| `cam4-fod-dt2w-20261121` | v5 | Mode video `s5khm6sx`, `vendor_name` `goodix_opt_tee` |
| `dlkm-cam3-dt2w-20261121` | v4 | `mtk-cam-isp` inline `sink_fmt`, `s5khm6sx` D-PHY 4-lane, flashlight core, touch gesture |
| `audio-aod-cam2-20261121` | v4 | Audio FS1599 PA + AOD/screen-on panel RM69220 terverifikasi |
| `dlkm-cam1-20261121` | v3 | Port 4 sensor kamera X6871 + `camera_eeprom_v4l2` |
| `vendor-boot-c3dfix-20261121` | v3 | C3D right pipe SRAM + `PQ_VIRTUAL_SET_PROPERTY` 12 B (layar normal penuh) |
| `dlkm-ocfix-20261121` | v2 | Fix spam IRQ battery OC 65 Hz + timing switch 144/120/60/40 Hz |
| `dlkm-20261120`..`gpu3` | v1 | DLKM 100% source (269 modul), `SCP_IPI_COUNT=59`, Mali r54p1-11eac0, `gpufreq_shared_status` |

Detail tiap rilis ada di [`docs/HANDOFF.md`](docs/HANDOFF.md) dan [`docs/PRETEST.md`](docs/PRETEST.md) §40–§65.

---

## Ringkasan Commit Penting (`x6871-android16-6.12`)

| Commit | Ringkasan |
|---|---|
| `33d0005` | `tran_audio_control`, `splitswitch-gpio`, `hiber` |
| `2b880e6` | Pixelworks Iris (34 file) di `mediatek_drm_v1` |
| `cfb098c` | Regulator `tran_ldo` (ET5904) |
| `381f45e`, `91640cd`..`28f5237`, `e6d0ab2` | Panel RM69220 X6871 (init table, DSC, rails, 4 mode 144/120/60/40 Hz) |
| `fdc1174`, `618a8c5` | `tc_common_class` + stack charger Transsion (`tc_*`) |
| `af55c9c` | `tran_extcon_usb`: role DEVICE/NONE/HOST saat cabut-colok |
| `5ba6fb6`, `5462a6d`, `07eb1da` | `SCP_IPI_COUNT=59`, GPU Mali r54p1-11eac0, layout `gpufreq_shared_status` |
| `1799bf1`, `e84137d`, `a765870` | C3D dual-pipe SRAM, PQ property 12 B, AOD panel |
| `75ca1ac`, `7aa967a`, `b86a4c8` | 4 sensor kamera X6871 + EEPROM, audio FS1599 |
| `6b45fda`..`17a6b66` | DRM AOD/HBM notifier ABI, DT2W+FOD touch, `/dev/goodix_fp`, VENC `VENC_H264=1` + ADAB + SLBC |

---

## Struktur Direktori

```text
.
├── local_manifest.xml      # Overlay manifest AOSP (6 project: 4 Moto + 2 repo alps X6871)
├── setup.sh                # Siapkan MODULE.bazel, symlink workspace, trim label mgk_64.bzl
├── build.sh                # Wrapper build Bazel+Kleaf
├── docs/                   # Dokumentasi status, panduan uji boot, log investigasi, tabel DT
├── scripts/                # Skrip baseline MTK, audit sumber, dan skrip porting historis
├── patches/                # Patch & sumber tambahan (ramdisk zstd, mtkcam X6871, tc_misc_intf)
└── tools/                  # Alat repack vendor_boot, daftar modul recovery, & audit biner .ko
```

| Lokasi | Fungsi |
|---|---|
| `local_manifest.xml` | Overlay manifest AOSP: 6 project (4 repo Motorola w1vo/w2we + `alps-kernel_device_modules-6.12` + `alps-vendor_mediatek_kernel_modules`) |
| `setup.sh` | Menyiapkan `MODULE.bazel`, symlink `common-6.12` & `../vendor/mediatek` (+ fallback symlink donor OPPO legacy), dan trim label `mgk_64.bzl` |
| `build.sh` | Wrapper build Bazel+Kleaf (`OVERLAYS=entry_level_legacy.config ./build.sh user`) |
| `docs/HANDOFF.md` | Status proyek, aturan keras, perintah build/repack, dan pengetahuan teknis kritis |
| `docs/BOOTTEST.md` | Prosedur flash, rollback, dan checklist uji boot per subsistem |
| `docs/PRETEST.md` | Log analisis statis, RE biner, dan investigasi bug (§1–§65) |
| `docs/PLAN.md` | Rencana porting awal dan catatan investigasi mendalam (§6.x) |
| `docs/DEVICES.md`, `docs/DEVICES-OVERLAY.md` | Pemetaan seluruh node Device Tree X6871 (base DTB + DTBO) ke driver |
| `scripts/reproduce-cleanup.sh` | Membuat branch `mtk-base-latest` (base MTK murni + 12 patch MTK) |
| `scripts/audit-sources.sh` | Mencocokkan `.ko` firmware ke berkas sumber berdasarkan isi simbol (bukan nama file) |
| `scripts/add-*.sh`, `scripts/patch-tc-misc-6.12.sh`, `scripts/port-tc-module.sh` | Skrip porting historis untuk driver Transsion, Iris, panel RM69220, `tran_ldo`, charger, dan kamera X6871 |
| `patches/` | Patch pendukung (`abie-zstd-ramdisk.patch`, `mtkcam-x6871-camera.patch`, `tc_misc_intf_6_12_extra.c`) |
| `tools/repack-vendor-boot-latest.sh` | **Repack utama `vendor_boot`**: build terbaru, stage 222 modul, pack TWRP zstd, dan verifikasi md5 per `.ko` |
| `tools/stage-recovery-modules.py` | Stage + strip modul dari staging Bazel dan regenerasi `modules.dep`/`alias`/`softdep` |
| `tools/recovery-modules.txt` | Daftar otoritatif 222 modul `vendor_boot` |
| `tools/modules.load`, `tools/modules.load.recovery` | Daftar muat init (`165` / `216` entri) |
| `tools/ko-preflight.py`, `tools/preboot-audit.py`, `tools/stock-vs-src.py` | Alat audit simbol/CRC/relokasi modul hasil build dibanding `.ko` stock |
| `tools/pack-vendor-boot.sh` | Tool legacy (memfilter nama stock) — **jangan dipakai untuk X6871** |

---

## Catatan Teknis Build

### Kenapa ada `scripts/reproduce-cleanup.sh`

Repo Motorola `kernel-kernel_device_modules-6.12` berisi 321 commit kode device (bogota/taipei/moto) di atas base MTK. Skrip ini mengambil base MTK murni lalu melakukan cherry-pick 12 patch MTK yang diperlukan:

```text
tree mtk-base-latest : fab94f37a9ee8a1d43828bdda55bc669e3138de6
```

### Kenapa `vendor/mediatek/kernel_modules` divendorkan terpadu

20 grup modul tidak dipublikasikan Motorola. 13 grup di antaranya berasal dari donor OPPO `mt6896` (Android 16 / kernel 6.12: `afs_common_utils`, `hbt_*`, `met_drv_v3`, `sched_cus`, `connectivity/*`), ditambah perubahan port X6871 di luar `kernel_device_modules-6.12` (GPU Mali r54p1-11eac0, `mtkcam` `camsys` inline `sink_fmt`, 4 sensor kamera X6871 + EEPROM). Seluruh 6 repo vendor Motorola + 13 modul donor OPPO + 4 commit port X6871 kini disatukan ke [`alps-vendor_mediatek_kernel_modules`](https://github.com/ramabondanp/alps-vendor_mediatek_kernel_modules/tree/x6871-android16-6.12) (branch `x6871-android16-6.12`), sehingga `repo sync` tidak lagi memerlukan `donor/oppo-mt6896` terpisah maupun symlink manual (`setup.sh` tetap mempertahankan fallback symlink untuk workspace split lama). Sisa 49 label di 20 grup internal/customer yang tidak tersedia tetap dihapus dari `mgk_64.bzl` oleh `setup.sh`:

```text
afs_core_cus/int  cpufreq_cus/int  fpsgo_cus/int  game_cus/int
gpio_sap_ctrl     met_drv_secure_v3  msync2_frd_cus/int  mtk_input
perf_common_cus/int  sched_int  task_turbo_cus/int
thinmd_exception  wwan
```

Kombinasi Motorola + donor OPPO ini sudah terbukti boot dan berjalan di Android 16 pada X6871 (Wi-Fi, GPU, audio, display, kamera foto).

### Tiga flag Bazel yang wajib

| Flag | Dampak jika hilang |
|---|---|
| `--user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers` | `fatal error: '<header>' file not found` di puluhan modul |
| `--repo_env=SUPPORT_PLATFORM=<soc>` | Semua 14 platform ikut dibangun dan gagal di modul platform lain |
| `--repo_env=KERNEL_VERSION=kernel-6.12` | Error `key "KERNEL_VERSION" not found` |

`--allow_ddk_unsafe_headers=1` saja tidak cukup karena daftar bawaan AOSP tidak memuat header privat MTK.

### Batasan

- Target `user_customer_abi` **tidak bisa lulus** di tree ini: `stg merge` gagal karena 328 simbol duplikat antar varian driver yang memang dibangun bersamaan (`fpsgo v3+v8`, `mediatek_v2+v1`, `tee gud 510/600/610/700`, `bt mt66xx+linux_v2`). Ini artefak build multi-varian, bukan mismatch KMI. Build referensi MTK/Samsung juga tidak menjalankan target ini.
- Untuk daftar jebakan build dan rincian status lengkap, lihat [`docs/HANDOFF.md`](docs/HANDOFF.md).

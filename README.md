# Manifest W1VO36.88-36-7 — Port Kernel Infinix GT 20 Pro (X6871)

Workspace Bazel+Kleaf untuk membangun modul kernel **Android 16 / kernel 6.12 / MediaTek MT6895**, berbasis tree Motorola W1VO36.88-36-7 dan diport penuh untuk **Infinix GT 20 Pro (X6871)**.

- **Branch port X6871**: [`w1vo36-6.12-port`](https://github.com/ramabondanp/alps-kernel_device_modules-6.12/tree/w1vo36-6.12-port) (`alps`, **90 commit** di atas baseline `06079c2`, HEAD `17a6b66d7927`)
- **Output build X6871**: staging **806 file** (**805** nama unik), flat customer install **702** `.ko`
- **Output baseline MTK murni** (`mtk-base-latest`): **1.401** `.ko`
- **Panduan cepat dokumen**:
  - `HANDOFF.md` — ringkasan status terkini, aturan kerja, perintah build/repack, dan pengetahuan kritis
  - `BOOTTEST.md` — prosedur flash, rollback, dan checklist uji boot per subsistem
  - `PRETEST.md` — log teknis kronologis (§1–§59) hasil audit statis, RE biner, dan uji device
  - `PLAN.md` — rencana porting awal dan bukti investigasi per modul (§6.x)
  - `DEVICES.md` / `DEVICES-OVERLAY.md` — tabel pemetaan node Device Tree X6871 ke driver

---

## Quickstart

### A. Build port Infinix X6871 (disarankan)

Branch `w1vo36-6.12-port` sudah memuat seluruh driver X6871 (panel RM69220, Pixelworks Iris, `tran_ldo`, stack charger Transsion, audio FS1599, 4 sensor kamera + EEPROM, flashlight, haptic, touch Goodix GT9916, optical fingerprint `tran_fp`, dan fix VENC/GPU/SCP).

```bash
git clone https://github.com/ramabondanp/w1vo36-kernel-manifest
cd w1vo36-kernel-manifest

# 1. Sync workspace AOSP + overlay manifest
mkdir -p ~/w1vo && cd ~/w1vo
repo init -u https://android.googlesource.com/kernel/manifest \
          -b common-android16-6.12-2025-09
cp ~/w1vo36-kernel-manifest/local_manifest.xml .repo/local_manifests/w1vo.xml
repo sync -j16

# 2. Checkout branch port X6871
cd kernel_device_modules-6.12
git remote add alps https://github.com/ramabondanp/alps-kernel_device_modules-6.12
git fetch alps w1vo36-6.12-port
git checkout -B w1vo36-6.12-port FETCH_HEAD
cd ..

# 3. Siapkan workspace, lalu build (overlay entry_level_legacy.config wajib untuk X6871)
~/w1vo36-kernel-manifest/setup.sh
OVERLAYS=entry_level_legacy.config ~/w1vo36-kernel-manifest/build.sh user
```

Hasil build berada di:
`out_bazel/*/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/`

### B. Build baseline MTK murni (tanpa driver X6871)

Gunakan langkah ini bila hanya ingin memverifikasi tree MTK bersih tanpa kode Motorola maupun Transsion:

```bash
cd ~/w1vo36-kernel-manifest
./reproduce-cleanup.sh ~/kernel-kernel_device_modules-6.12

cd ~/w1vo/kernel_device_modules-6.12
git remote add local ~/kernel-kernel_device_modules-6.12
git fetch local mtk-base-latest
git checkout -B mtk-base-latest FETCH_HEAD
cd ..

~/w1vo36-kernel-manifest/setup.sh
~/w1vo36-kernel-manifest/build.sh user
```

Untuk SoC lain: `PLATFORM=mt6991 ~/w1vo36-kernel-manifest/build.sh user` (default: `mt6895`).

> **Catatan branch**: `w1vo36-6.12-port` dibangun di atas baseline `06079c2` (yang merupakan keturunan langsung `android16` `30a0466a`) agar riwayat `android16` tidak berubah. Daftar lengkap commit: `git log --oneline 06079c2..HEAD`.

---

## Status Runtime & Rilis Terbaru (2026-11-22)

Seluruh partisi modul (**222** modul `vendor_boot` + **212** `vendor_dlkm` + **57** `odm_dlkm`) dibangun **100% dari source**.

### Status per subsistem

| Subsistem | Status | Catatan |
|---|---|---|
| Boot Android 16 & TWRP | ✅ Terbukti | Boot sampai launcher, 0 unresolved symbol |
| Layar RM69220 (144/120/60/40 Hz) & AOD | ✅ Terbukti | C3D dual-pipe + PQ ABI fixed, 0 underrun |
| GPU Mali r54p1-11eac0 & gpufreq | ✅ Terbukti | Donor OPPO + fix layout `gpufreq_shared_status` |
| Audio (MT6368 + FS1599 PA) | ✅ Terbukti | Kontrol `tran_audio_control` + PA switch aktif |
| Wi-Fi, USB replug, Charger, Haptic, Touch normal | ✅ Terbukti | Tidak ada spam IRQ battery OC |
| Kamera foto & preview video (4 sensor) | ✅ Terbukti | `s5khm6sx`, `gc32e1`, `gc02m3`, `gc02m3macro` + flashlight |
| **Rekam video (save)** | 🔄 Menunggu uji (`v10`) | Akar masalah ditemukan: `VENC_H264` salah = 13 (harus 1) + ADAB/SLBC ABI (`17a6b66d7927`) |
| **DT2W (termasuk saat AOD)** | 🔄 Menunggu uji (`v10`) | Fix enum notifier AOD (`6b45fdaa1ef1`) + `adaptive-ts` hanya resume di `AOD_NOTIFY` (`379924bf2586`) |
| **Optical FOD (fingerprint)** | 🔄 Menunggu uji (`v10`) | Fix `/dev/goodix_fp` + HBM uevent (`55aa13232a43`) + Goodix cmd `0x30` & key `195` (`379924bf2586`) |

### Rilis terbaru: `venc-fod-dt2w-20261122` (kernel `17a6b66d7927`)

```text
twrp-vendor_boot-allsrc-display-usb-v10.img  md5 3409f68913613b38d43052458435558b  67.108.864 B
twrp-dlkm-venc-fod-dt2w-20261122.zip         md5 92ab587de697a955fceba15ecf335d52
  ├─ vendor_dlkm.img                         md5 764c2d3f6fbd14aff802a0614ec7d014  24.551.424 B
  └─ odm_dlkm.img                            md5 af60243be2a87943f78fc7d254bb690a   4.206.592 B
```

Release GitHub: <https://github.com/ramabondanp/w1vo36-kernel-manifest/releases/tag/venc-fod-dt2w-20261122>

### Ringkasan perjalanan rilis

| Rilis | `vendor_boot` | Sorotan utama |
|---|---|---|
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

Detail tiap rilis ada di `HANDOFF.md` dan `PRETEST.md` §40–§59.

---

## Ringkasan Commit Penting (`w1vo36-6.12-port`)

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

## Daftar Berkas

| Berkas | Fungsi |
|---|---|
| `local_manifest.xml` | Overlay manifest AOSP: 12 project (11 repo Motorola w1vo/w2we + 1 donor OPPO mt6896) |
| `reproduce-cleanup.sh` | Membuat branch `mtk-base-latest` (base MTK murni + 12 patch MTK) |
| `setup.sh` | Menyiapkan `MODULE.bazel`, symlink donor OPPO & `../vendor/mediatek`, dan trim label `mgk_64.bzl` |
| `build.sh` | Wrapper build Bazel+Kleaf (`OVERLAYS=entry_level_legacy.config ./build.sh user`) |
| `add-*.sh`, `patch-tc-misc-6.12.sh`, `port-tc-module.sh` | Skrip porting historis untuk driver Transsion, Iris, panel RM69220, `tran_ldo`, charger, dan kamera X6871 |
| `audit-sources.sh` | Mencocokkan `.ko` firmware ke berkas sumber berdasarkan isi simbol (bukan nama file) |
| `tools/repack-vendor-boot-latest.sh` | **Repack utama `vendor_boot`**: build terbaru, stage 222 modul, pack TWRP zstd, dan verifikasi md5 per `.ko` |
| `tools/stage-recovery-modules.py` | Stage + strip modul dari staging Bazel dan regenerasi `modules.dep`/`alias`/`softdep` |
| `tools/recovery-modules.txt` | Daftar otoritatif 222 modul `vendor_boot` |
| `tools/modules.load`, `tools/modules.load.recovery` | Daftar muat init (`165` / `216` entri) |
| `tools/ko-preflight.py`, `tools/preboot-audit.py`, `tools/stock-vs-src.py` | Alat audit simbol/CRC/relokasi modul hasil build dibanding `.ko` stock |
| `tools/pack-vendor-boot.sh` | Tool legacy (memfilter nama stock) — **jangan dipakai untuk X6871** |
| `HANDOFF.md` | Status proyek, aturan keras, perintah build/repack, dan pengetahuan teknis kritis |
| `BOOTTEST.md` | Prosedur flash, rollback, dan checklist uji boot per subsistem |
| `PRETEST.md` | Log analisis statis, RE biner, dan investigasi bug (§1–§59) |
| `PLAN.md` | Rencana porting awal dan catatan investigasi mendalam (§6.x) |
| `DEVICES.md`, `DEVICES-OVERLAY.md` | Pemetaan seluruh node Device Tree X6871 (base DTB + DTBO) ke driver |

---

## Catatan Teknis Build

### Kenapa ada `reproduce-cleanup.sh`

Repo Motorola `kernel-kernel_device_modules-6.12` berisi 321 commit kode device (bogota/taipei/moto) di atas base MTK. Skrip ini mengambil base MTK murni lalu melakukan cherry-pick 12 patch MTK yang diperlukan:

```text
tree mtk-base-latest : fab94f37a9ee8a1d43828bdda55bc669e3138de6
```

### Kenapa ada donor OPPO

20 grup modul tidak dipublikasikan Motorola. 13 grup di antaranya tersedia di donor OPPO `mt6896` (Android 16 / kernel 6.12) dan di-symlink oleh `setup.sh` (`afs_common_utils`, `hbt_*`, `met_drv_v3`, `sched_cus`, `connectivity/*`, serta tree GPU Mali r54p1-11eac0). Sisanya (49 label di 20 grup internal/customer) dihapus dari `mgk_64.bzl` oleh `setup.sh`:

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
- Untuk daftar jebakan build dan rincian status lengkap, lihat `HANDOFF.md`.

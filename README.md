# Manifest W1VO36.88-36-7

Workspace kernel Motorola W1VO36.88-36-7 (Android 16 / kernel 6.12.38 /
MediaTek mt6895), dibangun dengan Bazel+Kleaf.

## Quickstart

```bash
git clone https://github.com/ramabondanp/w1vo36-kernel-manifest
cd w1vo36-kernel-manifest

# 1. Buat branch kernel_device_modules yang sudah dibersihkan dari kode Moto
./reproduce-cleanup.sh ~/kernel-kernel_device_modules-6.12

# 2. Sync workspace AOSP + overlay
mkdir -p ~/w1vo && cd ~/w1vo
repo init -u https://android.googlesource.com/kernel/manifest \
          -b common-android16-6.12-2025-09
cp ~/w1vo36-kernel-manifest/local_manifest.xml .repo/local_manifests/w1vo.xml
repo sync -j16

# 3. Pasang branch hasil cleanup
cd kernel_device_modules-6.12
git remote add local ~/kernel-kernel_device_modules-6.12
git fetch local mtk-base-latest
git checkout -B mtk-base-latest FETCH_HEAD
cd ..

# 4. Siapkan workspace, lalu build
~/w1vo36-kernel-manifest/setup.sh
~/w1vo36-kernel-manifest/build.sh user
```

Hasil baseline MTK murni: `1.401 .ko` di
`out_bazel/*/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/`.
Branch port di bawah menghasilkan staging 806 file / 805 nama unik dan flat
customer install 702 `.ko`.

Soc lain: `PLATFORM=mt6991 ./build.sh user` (default `mt6895`).

### Branch port (sudah termasuk semua driver X6871)

`mtk-base-latest` di langkah 3 hanya MTK murni. Semua pekerjaan port
(Iris, panel rm69220, `tran_ldo`, fondasi charger Transsion) ada di branch
terpisah, ter-push ke remote `alps`:

```bash
cd kernel_device_modules-6.12
git remote add alps https://github.com/ramabondanp/alps-kernel_device_modules-6.12
git fetch alps w1vo36-6.12-port
git checkout -B w1vo36-6.12-port FETCH_HEAD

cd ..
~/w1vo36-kernel-manifest/setup.sh
~/w1vo36-kernel-manifest/build.sh user
# staging: 806 .ko (805 nama unik), flat customer install: 702 .ko
```

Branch: <https://github.com/ramabondanp/alps-kernel_device_modules-6.12/tree/w1vo36-6.12-port>

Branch ini dibuat baru (bukan di atas `android16`) supaya riwayat `android16`
tidak tersentuh. `android16` (`30a0466a`) memang ancestor dari baseline
w1vo36.88-36-7 (`06079c2`), jadi branch ini juga fast-forward-able ke sana.

Branch berisi **65 commit** di atas `06079c2`, satu commit per fitur.
Ringkasan commit awal dan commit final yang penting:

| commit | isi |
|---|---|
| `33d0005` | `tran_audio_control`, `splitswitch-gpio`, `hiber` |
| `2b880e6` | Iris (34 file, Pixelworks) |
| `cfb098c` | `tran_ldo` (ET5904) |
| `381f45e` | panel rm69220 X6871 (versi awal) |
| `fdc1174` | `tc_common_class` (fondasi `tran_device`) |
| `618a8c5` | `tc_charger_class`/`adapter`/`algorithm`/`misc_intf` |
| `91640cd`..`28f5237` | panel final: init table, DSC, rails, 8bpc/1056 Mbps |
| `af55c9c` | `tran_extcon_usb`: role DEVICE/NONE/HOST saat cabut-colok |

Daftar lengkap: `git log --oneline 06079c2..HEAD`.

## Status runtime (2026-11-21)

TWRP memakai **222 modul, 100% hasil build sendiri**. Image final yang
sudah diuji:

```text
twrp-vendor_boot-allsrc-display-usb.img
md5 0ecdaa1edb3d405954331539b24c911b
```

Yang sudah terverifikasi: layar mati -> nyala (0 buffer underrun) dan
cabut-colok USB berulang (setiap colok kembali `online=1, type=1` SDP,
`pullup D+`, `gadget RESET`). Image dlkm 100% source juga sudah siap
(release `dlkm-20261120`, 269 modul; detail `PRETEST.md` §45).
Percobaan boot system berhenti berurutan di SCP, Mali, lalu
shared-status gpufreq: `SCP_IPI_COUNT` 59 (`5ba6fb6559ab`), GPU donor
OPPO r54p1-11eac0 (`5462a6d118a6`), dan padding gpufreq sebelum
`power_count` (`07eb1dab07c2`), hingga akhirnya **boot sampai launcher +
Wi-Fi + Mali GPU** (`dmesg4`). Fix berikutnya menutup spam IRQ battery OC
65 Hz (`8d38cd08a65c`), skala gauge `r-fg-value` (`0f7ce1ce8f7e`), timing/VFP
mode switch 144/120/60/40 Hz panel (`e6d0ab2fb66a`, release `dlkm-ocfix-20261121`),
serta bug layar setengah kanan pink/hijau akibat `disp_c3d_check_sram` right pipe
(`1799bf13b78b`) dan ukuran `PQ_VIRTUAL_SET_PROPERTY` (`e84137d0e2aa`) di
`mediatek_drm_v1.ko` (release `vendor-boot-c3dfix-20261121`, **layar normal
penuh**). Driver kamera X6871 (4 sensor `s5khm6sx`/`gc32e1`/`gc02m3`/`gc02m3macro`
+ `camera_eeprom_v4l2`, `75ca1ac4a1ae` + `add-camera-x6871.sh`) di-repack di
`dlkm-cam1-20261121`; fix audio FS1599 (`7aa967a7ba5a`, `b86a4c8cdca3`) dan
AOD/screen-on panel (`a765870ac11f`) **terkonfirmasi normal** di `audio-aod-cam2-20261121`;
fix lanjutan `mtk-cam-isp` inline `sink_fmt`, `s5khm6sx` D-PHY 4-lane,
Transsion `flashlight-core` (`1d3f17a21434`), dan DT2W/FOD touch
`adaptive-ts`+`gt9916_common` (`466e4c1731c1`) menghidupkan kamera foto;
release terbaru `vid-fl-dt2w5-20261121` (`vendor_boot` v6 + `vendor_dlkm` +
`odm_dlkm`) memperbaiki layar hijau intermiten (C3D, `d46c6e7de494`), simpan video
(`max_qp[3]`, `79cacb884584`), flashlight `ocp81375_v4l2` (`b2de4bc7507e`), dan DT2W
KEY 198 (`3c5e64704b34`); rilis sebelumnya `cam4-fod-dt2w-20261121` memperbaiki mode video
`s5khm6sx`, `vendor_name` `goodix_opt_tee`, dan retry bangun tidur. Detail: `HANDOFF.md`,
`PRETEST.md` §40-§55.

Catatan: hasil port di-push ke branch `w1vo36-6.12-port` di remote `alps`
(bukan ke `mtk-base-latest`, yang sedang checked-out di working tree lokal).


## File

| File | Isi |
|---|---|
| `local_manifest.xml` | 13 project w1vo + donor OPPO, overlay ke manifest AOSP |
| `reproduce-cleanup.sh` | buat branch `mtk-base-latest` (MTK murni + 12 patch) |
| `setup.sh` | MODULE.bazel, symlink donor + `../vendor/mediatek`, trim label |
| `build.sh` | build module (`./build.sh user`) |
| `add-transsion.sh` | tambah 3 modul Transsion mandiri dari donor mt6897 |
| `add-iris.sh` | pasang Pixelworks Iris ke `mediatek_drm_v1` + patch 6.12 |
| `add-panel-rm69220.sh` | panel X6871: init table + timing hasil ekstrak firmware |
| `add-tran-ldo.sh` | regulator `tran_ldo` (ET5904) — sumber `TRANLDO26` untuk panel |
| `add-tc-common-class.sh` | fondasi `tran_device` API — dipakai 19 modul firmware |
| `add-tc-charger-stack.sh` | fondasi charger Transsion: `tc_charger_class` + `tc_adapter_class` + `tc_algorithm_class` + `tc_misc_intf` |
| `patch-tc-misc-6.12.sh` | 8 fungsi `tc_misc_intf` tambahan 6.12, rekonstruksi dari `.ko` |
| `audit-sources.sh` | cocokkan modul firmware -> file source **tanpa** peduli nama file |
| `tools/ko-preflight.py` | bandingkan 4 modul fitur dengan `.ko` stock (export/impor/CRC/call graph) |
| `tools/preboot-audit.py` | audit **seluruh** modul stock yang digantikan build: 1 baris per `.ko` firmware, plus simulasi loader pada set itu |
| `tools/stock-vs-src.py` | bandingkan source vs `.ko` stock (dipakai audit kamera, `PRETEST.md` §26) |
| `tools/repack-vendor-boot-latest.sh` | **repack utama X6871**: build source terbaru, stage 222 modul dari Bazel, pack, lalu verifikasi tiap `.ko` di image sama dengan staging |
| `tools/stage-recovery-modules.py` | stage + strip modul dari staging, regenerasi `modules.dep`/`alias`/`softdep` |
| `tools/recovery-modules.txt` | daftar 222 modul recovery (sumber kebenaran komposisi vendor_boot) |
| `tools/modules.load`, `tools/modules.load.recovery` | daftar muat init, 165 / 216 entri |
| `tools/pack-vendor-boot.sh` | legacy: repack dari image stock + filter nama stock; jangan dipakai untuk X6871 (lihat `HANDOFF.md`) |
| `BOOTTEST.md` | prosedur uji boot utuh: artefak, flash, rollback, checklist per subsistem, delta yang wajar |
| `PLAN.md` | rencana port driver device lain (X6871) — Tingkat A sudah selesai |

## Kenapa ada `reproduce-cleanup.sh`

Repo Motorola `kernel-kernel_device_modules-6.12` berisi 321 commit kode
device (bogota/taipei/moto) di atas base MTK. Script ini checkout base MTK
murni lalu cherry-pick 12 patch MTK yang diperlukan.

Hasil terverifikasi identik dengan branch referensi:

```
tree mtk-base-latest : fab94f37a9ee8a1d43828bdda55bc669e3138de6
```

## Kenapa ada donor OPPO

20 grup module tidak dipublikasikan Motorola. 13 di antaranya ada di donor
OPPO mt6896 dan di-symlink oleh `setup.sh`. Sisanya (49 label) dihapus dari
`mgk_64.bzl` oleh `setup.sh`:

```
afs_core_cus/int  cpufreq_cus/int  fpsgo_cus/int  game_cus/int
gpio_sap_ctrl     met_drv_secure_v3  msync2_frd_cus/int  mtk_input
perf_common_cus/int  sched_int  task_turbo_cus/int
thinmd_exception  wwan
```

Module donor **ikut ter-build** dan masuk output (afs_common_utils, hbt_*,
met_drv_v3, sched_cus, connectivity/*). Campuran Moto+OPPO ini belum diuji
runtime.

## Tiga flag yang wajib

Kalau salah satu hilang, build gagal:

| Flag | Tanpa ini |
|---|---|
| `--user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers` | `fatal error: '<header>' file not found` di puluhan module |
| `--repo_env=SUPPORT_PLATFORM=<soc>` | semua 14 platform ikut dibangun, gagal di module platform lain |
| `--repo_env=KERNEL_VERSION=...` | `key "KERNEL_VERSION" not found` |

`--allow_ddk_unsafe_headers` saja tidak cukup — itu hanya mengaktifkan daftar
bawaan AOSP yang tidak memuat header MTK.

## Batasan

- `user_customer_abi` **tidak bisa lulus** di tree ini: `stg merge` gagal
  karena 328 simbol duplikat antar varian driver yang memang dibangun
  bersamaan (fpsgo v3+v8, mediatek_v2+v1, tee gud 510/600/610/700,
  bt mt66xx+linux_v2). Ini artefak build multi-varian, bukan mismatch KMI.
  Build referensi MTK/Samsung juga tidak menjalankan target ABI.
- Detail status dan jebakan: lihat `HANDOFF.md`.

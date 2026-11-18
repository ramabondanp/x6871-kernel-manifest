# Manifest W1VO36.88-36-7

Workspace kernel Motorola W1VO36.88-36-7 (Android 16 / kernel 6.12):

- 11 repo yang punya branch `android-16-release-w1vo36.88-36-7`
- 1 donor repo OPPO mt6896 (Android 16 / 6.12) untuk module yang tidak
  dipublikasikan Motorola

## File

| File | Pakai untuk |
|---|---|
| `default.xml` | workspace berdiri sendiri (12 repo) |
| `local_manifest.xml` | overlay ke manifest AOSP 2025-09 (disarankan) |
| `post-sync.sh` | MODULE.bazel MGK include, symlink common-6.12, symlink module donor |
| `trim-missing.sh` | hapus label `//vendor/...` yang tidak tersedia |

## Cara 1 - overlay AOSP (disarankan)

Manifest AOSP dipakai untuk Kleaf + prebuilts + dependency bzlmod,
lalu kernel/common dan kernel/build diganti versi w1vo.

```bash
git clone https://github.com/ramabondanp/w1vo36-kernel-manifest

mkdir w1vo && cd w1vo
repo init -u https://android.googlesource.com/kernel/manifest \
          -b common-android16-6.12-2025-09
cp ../w1vo36-kernel-manifest/local_manifest.xml .repo/local_manifests/w1vo.xml
repo sync -j8
../w1vo36-kernel-manifest/post-sync.sh
```

Hasil:

```
build/kernel/                  <- kernel-build-kernel (w1vo)
build/bazel_mgk_rules/         <- kernel-build-bazel_mgk_rules (w1vo)
kernel-6.12/                   <- kernel-mtk (6.12.38 + GKI 2025-09_r32)
kernel_device_modules-6.12/    <- repo ini
motorola/kernel/modules/       <- motorola-kernel-modules
vendor/mediatek/kernel_modules/{gpu,mtkcam,connectivity/...}
donor/oppo-mt6896/             <- donor OPPO
prebuilts/...                  <- dari manifest AOSP
tools/bazel                    <- linkfile dari build/kernel
```

## Cara 2 - standalone

```bash
mkdir w1vo-kernel && cd w1vo-kernel
repo init -u https://github.com/ramabondanp/w1vo36-kernel-manifest -b main
repo sync -j8
```

Belum langsung bisa build: `prebuilts/clang/host/linux-x86` dan dependency
Kleaf lain tidak ada di 12 repo ini. Pakai Cara 1 kalau mau langsung build.

## Donor OPPO

`oppo-source/android_kernel_modules_oppo_mt6896`
branch `oppo/mt6896_b_16.0_reno12`, path `donor/oppo-mt6896`.

Isinya yang dipakai (di-symlink `post-sync.sh`):

```
vendor/mediatek/kernel_modules/
  afs_common_utils
  hbt_driver
  hbt_driver_cus
  met_drv_v3
  sched_cus
  connectivity/common
  connectivity/connfem
  connectivity/fmradio
  connectivity/gps
  connectivity/wlan/adaptor
  connectivity/wlan/core/gen4-mt79xx
  connectivity/bt/linux_v2_ce
  connectivity/bt/mt76xx
```

Catatan: donor ini dari OPPO mt6896. Untuk module yang sudah ada versi
w1vo (gpu, mtkcam, conninfra, bt/linux_v2, bt/mt66xx, wlan/core/gen4m),
versi w1vo yang dipakai. Campuran ini belum tentu ABI-compatible.

## Module yang tetap tidak ada

20 grup module tidak ada di w1vo maupun donor:

```
afs_core_cus / afs_core_int
cpufreq_cus / cpufreq_int
fpsgo_cus / fpsgo_int
game_cus / game_int
gpio_sap_ctrl
met_drv_secure_v3
msync2_frd_cus / msync2_frd_int
mtk_input
perf_common_cus / perf_common_int
sched_int
task_turbo_cus / task_turbo_int
thinmd_exception
wwan
```

Jalankan ini supaya label-label itu tidak dicari Bazel:

```bash
./trim-missing.sh
```

Script menghapus 49 baris dari `kernel_device_modules-6.12/kernel/kleaf/mgk_64.bzl`
(backup ke `mgk_64.bzl.orig`) dan tidak menyentuh kode lain.

## Build

```bash
export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1
tools/bazel build \
  --//build/bazel_mgk_rules:kernel_version=6.12 \
  --experimental_writable_outputs \
  //kernel_device_modules-6.12:mgk_64_k612_internal_modules_install.user

tools/bazel run \
  --//build/bazel_mgk_rules:kernel_version=6.12 \
  --nokmi_symbol_list_violations_check \
  //kernel_device_modules-6.12:mgk_64_k612_internal_dist.user \
  -- --dist_dir=out_krn/dist
```

Di tree Android MTK lengkap:

```bash
source build/envsetup.sh
export OUT_DIR=out_krn
lunch krn_mgk_64_k612-userdebug
make -j$(nproc) krn_images
```

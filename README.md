# Manifest W1VO36.88-36-7

Semua repo di bawah punya branch `android-16-release-w1vo36.88-36-7`
(hasil scan 312 repo public MotorolaMobilityLLC).

## File

| File | Pakai untuk |
|---|---|
| `default.xml` | workspace kernel berdiri sendiri (11 repo w1vo) |
| `local_manifest.xml` | overlay ke manifest AOSP 2025-09 (cara yang disarankan) |

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
```

Hasil:

```
build/kernel/                  <- kernel-build-kernel (w1vo)
build/bazel_mgk_rules/         <- kernel-build-bazel_mgk_rules (w1vo)
kernel-6.12/                   <- kernel-mtk (w1vo, 6.12.38 + GKI 2025-09_r32)
kernel_device_modules-6.12/    <- repo ini
motorola/kernel/modules/       <- motorola-kernel-modules
vendor/mediatek/kernel_modules/{gpu,mtkcam,connectivity/...}
prebuilts/...                  <- dari manifest AOSP
tools/bazel                    <- linkfile dari build/kernel
```

Build:

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

## Cara 2 - standalone

```bash
mkdir w1vo-kernel && cd w1vo-kernel
repo init -u https://github.com/ramabondanp/w1vo36-kernel-manifest -b main
repo sync -j8
```

Tapi cara ini **belum bisa langsung build**: `prebuilts/clang/host/linux-x86`
dan dependency Kleaf lainnya tidak ada di 11 repo w1vo. Tambahkan manual
dari AOSP atau pakai Cara 1.

## Yang TIDAK ada di manifest ini

`EXT_MODULES` di `build.config.mtk_kernel_device_modules` dan 198 label
`//vendor/mediatek/kernel_modules/...` di `mgk_64.bzl` juga memakai module
yang tidak punya branch w1vo:

```
connectivity/common        connectivity/connfem
connectivity/gps           connectivity/fmradio
connectivity/wlan/adaptor  hbt_driver_cus
afs_common_utils           afs_core_cus / afs_core_int
cpufreq_cus / cpufreq_int  fpsgo_cus / fpsgo_int
game_cus / game_int        met_drv_v3
```

Repo-repo itu cuma punya branch lain (`android-16-release-w1ve36h.10-12r3`
dll) atau tidak ada branch android-16 sama sekali.

Kalau build gagal karena label `//vendor/...` tidak ketemu, ada 2 pilihan:

1. Ambil repo tsb dari branch `android-16-release-w1ve36h.10-12r3`.
2. Pangkas daftar `kleaf_modules` / `EXT_MODULES` di `mgk_64.bzl` dan
   `build.config.mtk_kernel_device_modules` sesuai module yang ada.

## Catatan

- Branch `motorola/kernel/modules` diambil dari `kernel_helpers.bzl`
  (`//motorola/kernel/modules:public_headers`).
- `kernel-6.12` = repo `kernel-mtk`, bukan `kernel/common` AOSP.
- Kalau mau murni MTK, hapus baris `motorola/kernel/modules` dari manifest.

## Setelah sync

Jalankan:

```bash
./post-sync.sh
```

Script itu:

1. Mengganti symlink `MODULE.bazel` dengan file biasa, lalu menambah
   `include("//build/bazel_mgk_rules/bzlmod:mgk_repo.MODULE.bazel")`.
   Tanpa ini `@mgk_info` tidak ada dan `//kernel_device_modules-6.12` gagal load.
2. Membuat symlink `common-6.12 -> kernel-6.12` (dipakai `mgk.bzl`
   untuk build varian `ack`).

Verifikasi cepat tanpa build penuh:

```bash
tools/bazel query //kernel_device_modules-6.12:all
```

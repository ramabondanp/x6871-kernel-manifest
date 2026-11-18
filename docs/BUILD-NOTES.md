# Build kernel_device_modules-6.12 (project W1VO36.88-36-7)

## Sumber (semua branch: android-16-release-w1vo36.88-36-7)

| Repo | Peran |
|---|---|
| kernel-mtk | **full MTK ACK kernel** (6.12.38, GKI 2025-09_r32, 22 file dipatch) |
| kernel_device_modules-6.12 | repo ini (DDK modules) |
| kernel-build-kernel | Kleaf (build/kernel) |
| kernel-build-bazel_mgk_rules | MGK rules (build/bazel_mgk_rules) |
| motorola-kernel-modules | module Moto out-of-tree (moto_binder, moto_mm, utags, dll) |
| vendor-mediatek-kernel_modules-gpu | GPU |
| vendor-mediatek-kernel_modules-mtkcam | Camera |
| vendor-mediatek-kernel_modules-connectivity-conninfra | Conninfra |
| vendor-mediatek-kernel_modules-connectivity-bt-linux_v2 | BT |
| vendor-mediatek-kernel_modules-connectivity-bt-mt66xx | BT |
| vendor-mediatek-kernel_modules-connectivity-wlan-core-gen4m | WLAN |

## Layout workspace (root = <android-root>/kernel)

    kernel/                                  <- Bazel workspace
      tools/bazel -> build/kernel/kleaf/bazel.sh
      build/kernel/                          <- kernel-build-kernel
      build/bazel_mgk_rules/                 <- kernel-build-bazel_mgk_rules
      kernel-6.12/                           <- kernel-mtk
      kernel_device_modules-6.12/            <- repo ini
      vendor/mediatek/kernel_modules/        <- vendor repos
          gpu/ mtkcam/ connectivity/...

## Build

    source build/envsetup.sh
    export OUT_DIR=out_krn
    lunch krn_mgk_64_k612-userdebug
    make -j$(nproc) krn_images

atau standalone:

    export KERNEL_DIR=kernel_device_modules-6.12
    export BUILD_CONFIG=kernel_device_modules-6.12/build.config.mtk_kernel_device_modules
    export PROJECT=mgk_64_k612
    export MODE=user
    export OUT_DIR=$PWD/out_krn
    ./kernel_device_modules-6.12/build.sh

atau bazel langsung (dari workspace kernel/):

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

## GKI

- ACK base : android16-6.12-2025-09_r32 (dari commit message kernel-mtk)
- KMI      : generation 5 (sama untuk tag 2025-06 s/d 2025-09)
- Kernel   : 6.12.38
- ack_headers: 4184 / 4185 path cocok (1 stale: drivers/thermal/thermal.h)

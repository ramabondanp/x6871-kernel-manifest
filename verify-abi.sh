#!/bin/bash
# Verifikasi ABI device modules terhadap GKI ABI (gki/aarch64/abi.stg).
# Jalankan dari root workspace, setelah module berhasil dibuild.
#
#   ./verify-abi.sh            # user
#   ./verify-abi.sh userdebug
set -e

VARIANT=${1:-user}

SCOPE=customer
[ -d vendor/mediatek/tests/kernel ] && SCOPE=internal

TARGET="//kernel_device_modules-6.12:mgk_64_k612.${VARIANT}_${SCOPE}_abi"

echo "target: $TARGET"

export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1

exec tools/bazel --output_user_root="$PWD/out_bazel" build \
  --repo_env=KERNEL_VERSION=kernel-6.12 \
  --repo_env=KERNEL_BUILD_VARIANT="$VARIANT" \
  --repo_env=DEFCONFIG_OVERLAYS= \
  --repo_env=SUPPORT_PLATFORM= \
  --repo_env=SOURCE_DATE_EPOCH=0 \
  --//build/bazel_mgk_rules:kernel_version=6.12 \
  --experimental_writable_outputs \
  "$TARGET"

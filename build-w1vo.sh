#!/bin/bash
# Build kernel_device_modules-6.12 (w1vo workspace).
# Jalankan dari root workspace (yang ada build/, kernel-6.12/, tools/bazel).
#
#   ./build-w1vo.sh            # user
#   ./build-w1vo.sh userdebug
#   ./build-w1vo.sh eng
#
# Env KERNEL_VERSION dkk harus lewat --repo_env, bukan export biasa:
# mgk_extension.bzl membaca module_ctx.os.environ.
set -e

VARIANT=${1:-user}

SCOPE=customer
[ -d vendor/mediatek/tests/kernel ] && SCOPE=internal

TARGET="//kernel_device_modules-6.12:mgk_64_k612_${SCOPE}_modules_install.${VARIANT}"

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

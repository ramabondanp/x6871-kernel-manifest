#!/bin/bash
# Build kernel_device_modules-6.12 (w1vo). Jalankan dari root workspace.
#
#   ./build.sh              # user, mt6895, tanpa overlay (baseline)
#   ./build.sh user userdebug
#   PLATFORM=mt6991 ./build.sh user
#   OVERLAYS=entry_level_legacy.config ./build.sh user
#
# OVERLAYS: nama file di kernel_device_modules-6.12/kernel/configs/,
# dipisah spasi. Contoh yang sudah diverifikasi:
#   entry_level_legacy.config  -> +13 modul (angka absolut berubah setelah
#                                 port X6871; lihat PLAN.md/HANDOFF.md)
#
# Perintah ini sudah diverifikasi: 1.401 .ko baseline MTK murni, 0 error.
# Branch port X6871 + OVERLAYS=entry_level_legacy.config: 806 file staging
# (805 nama unik), flat customer install 702 .ko. Lihat HANDOFF.md.
#
# Tiga hal yang wajib, semuanya dari build.sh MTK/Samsung asli:
#   --allow_ddk_unsafe_headers=1
#   --user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers
#     ^ ini yang membuat header privat kernel terlihat di sandbox DDK.
#       --allow_ddk_unsafe_headers saja TIDAK cukup (daftar AOSP tidak
#       memuat header MTK) -> "fatal error: file not found".
#   --repo_env=SUPPORT_PLATFORM=<soc>
#     ^ tanpa ini semua 14 platform ikut dibangun.
set -e

VARIANT=${1:-user}
PLATFORM=${PLATFORM:-mt6895}
OVERLAYS=${OVERLAYS:-}

# Jangan pakai /tmp. Override dengan TMPDIR=... kalau perlu.
export TMPDIR=${TMPDIR:-$PWD/../tmp}
mkdir -p "$TMPDIR"

SCOPE=customer
[ -d vendor/mediatek/tests/kernel ] && SCOPE=internal

TARGET="//kernel_device_modules-6.12:mgk_64_k612_${SCOPE}_modules_install.${VARIANT}"
OUT=${OUT_DIR:-$PWD/out_bazel}

echo "target  : $TARGET"
echo "platform: $PLATFORM"
echo "variant : $VARIANT"
echo "overlays: ${OVERLAYS:-(tidak ada)}"

export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1

exec tools/bazel --output_user_root="$OUT" build \
  --config=stamp \
  --repo_manifest="$PWD/kernel_device_modules-6.12/fake_manifest.xml" \
  --experimental_writable_outputs \
  --allow_ddk_unsafe_headers=1 \
  --user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers \
  --repo_env=KERNEL_VERSION=kernel-6.12 \
  --repo_env=KERNEL_BUILD_VARIANT="$VARIANT" \
  --repo_env=DEFCONFIG_OVERLAYS="$OVERLAYS" \
  --repo_env=SUPPORT_PLATFORM="$PLATFORM" \
  --repo_env=SOURCE_DATE_EPOCH=0 \
  --//build/bazel_mgk_rules:kernel_version=6.12 \
  "$TARGET"

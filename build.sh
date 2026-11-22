#!/bin/bash
# Build kernel_device_modules-6.12 (Infinix GT 20 Pro / X6871, MT6895).
# Jalankan dari root workspace kernel.
#
#   ./build.sh                              # user, mt6895, overlay X6871
#   ./build.sh userdebug                    # userdebug, mt6895, overlay X6871
#   OVERLAYS="" ./build.sh user             # tanpa overlay (untuk baseline MTK murni)
#   PLATFORM=mt6991 ./build.sh user         # override SoC target
#
# OVERLAYS: nama file di kernel_device_modules-6.12/kernel/configs/,
# dipisah spasi. Default: entry_level_legacy.config X6871.config
# (set OVERLAYS="" untuk menonaktifkan). Lihat docs/PLAN.md & docs/HANDOFF.md.
#
# Output terverifikasi:
#   - Port X6871 (x6871-android16-6.12, KMI 6): 553 file staging (552 unik), 419 .ko flat (413 target OOT X6871)
#   - Baseline MTK murni (mtk-base-latest, OVERLAYS=""): 1.401 .ko, 0 error
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

[ -x tools/bazel ] || { echo "ERROR: jalankan dari root workspace kernel (tools/bazel tidak ada)"; exit 1; }

VARIANT=${1:-user}
PLATFORM=${PLATFORM:-mt6895}
OVERLAYS=${OVERLAYS-entry_level_legacy.config X6871.config}

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

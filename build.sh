#!/bin/bash
# Build kernel_device_modules-<KVER> (Infinix GT 20 Pro / X6871, MT6895).
# Jalankan dari root workspace kernel.
#
#   ./build.sh                              # user, mt6895, overlay X6871 (KVER=6.12)
#   KVER=6.18 ./build.sh user               # profil PLAN-6.18 (GKI common, KMI 5)
#   KVER=6.18 ./build.sh gki                # build lokal boot-lz4.img + system_dlkm 6.18
#   ./build.sh userdebug                    # userdebug, mt6895, overlay X6871
#   OVERLAYS="" ./build.sh user             # tanpa overlay (untuk baseline MTK murni)
#   PLATFORM=mt6991 ./build.sh user         # override SoC target
#
# OVERLAYS: nama file di kernel_device_modules-<KVER>/kernel/configs/,
# dipisah spasi. Default: entry_level_legacy.config X6871.config
# (set OVERLAYS="" untuk menonaktifkan). Lihat docs/guides/BUILD.md.
#
# Output terverifikasi 6.12:
#   - Port X6871 (x6871-android16-6.12, KMI 6): 553 file staging (552 unik), 419 .ko flat (413 target OOT X6871)
#   - Baseline MTK murni (mtk-base-latest, OVERLAYS=""): 1.401 .ko, 0 error
#
# Tiga hal yang wajib, semuanya dari build.sh MTK/Samsung asli:
#   --allow_ddk_unsafe_headers=1
#   --user_ddk_unsafe_headers=//kernel_device_modules-<KVER>:mtk_use_gki_unsafe_headers
#     ^ ini yang membuat header privat kernel terlihat di sandbox DDK.
#       --allow_ddk_unsafe_headers saja TIDAK cukup (daftar AOSP tidak
#       memuat header MTK) -> "fatal error: file not found".
#   --repo_env=SUPPORT_PLATFORM=<soc>
#     ^ tanpa ini semua 14 platform ikut dibangun.
set -e

[ -x tools/bazel ] || { echo "ERROR: jalankan dari root workspace kernel (tools/bazel tidak ada)"; exit 1; }

KVER=${KVER:-6.12}
KCODE=64_k6${KVER#6.}
TREE=kernel_device_modules-$KVER
VARIANT=${1:-user}
PLATFORM=${PLATFORM:-mt6895}
OVERLAYS=${OVERLAYS-entry_level_legacy.config X6871.config}

# Jangan pakai /tmp. Override dengan TMPDIR=... kalau perlu.
export TMPDIR=${TMPDIR:-$PWD/../tmp}
mkdir -p "$TMPDIR"

SCOPE=customer
[ -d vendor/mediatek/tests/kernel ] && SCOPE=internal

TARGET="//$TREE:mgk_${KCODE}_${SCOPE}_modules_install.${VARIANT}"
OUT=${OUT_DIR:-$PWD/out_bazel}

export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1

if [ "$VARIANT" = "gki" ]; then
  [ "$KVER" = "6.18" ] || { echo "ERROR: mode gki hanya untuk KVER=6.18" >&2; exit 1; }
  echo "kernel  : $KVER (common GKI images)"
  echo "targets : //common:kernel_aarch64_gki_artifacts //common:kernel_aarch64_system_dlkm_image"
  [ -n "${LOCALVERSION_SUFFIX:-}" ] && echo "suffix  : $LOCALVERSION_SUFFIX"
  exec tools/bazel --output_user_root="$OUT" build \
    --config=stamp \
    --repo_manifest="$PWD/$TREE/fake_manifest.xml" \
    //common:kernel_aarch64_gki_artifacts \
    //common:kernel_aarch64_system_dlkm_image
fi

echo "kernel  : $KVER ($TREE)"
echo "target  : $TARGET"
echo "platform: $PLATFORM"
echo "variant : $VARIANT"
echo "overlays: ${OVERLAYS:-(tidak ada)}"

exec tools/bazel --output_user_root="$OUT" build \
  --config=stamp \
  --repo_manifest="$PWD/$TREE/fake_manifest.xml" \
  --experimental_writable_outputs \
  --allow_ddk_unsafe_headers=1 \
  --user_ddk_unsafe_headers=//$TREE:mtk_use_gki_unsafe_headers \
  --repo_env=KERNEL_VERSION=kernel-$KVER \
  --repo_env=KERNEL_BUILD_VARIANT="$VARIANT" \
  --repo_env=DEFCONFIG_OVERLAYS="$OVERLAYS" \
  --repo_env=SUPPORT_PLATFORM="$PLATFORM" \
  --repo_env=SOURCE_DATE_EPOCH=0 \
  --//build/bazel_mgk_rules:kernel_version=$KVER \
  "$TARGET"

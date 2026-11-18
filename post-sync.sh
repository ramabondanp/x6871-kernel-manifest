#!/bin/bash
# Jalankan dari root workspace setelah `repo sync`.
#
# 1. Tambah include MGK ke MODULE.bazel (linkfile AOSP belum memuatnya).
# 2. Buat symlink common-6.12 -> kernel-6.12 (dipakai mgk.bzl varian "ack").
# 3. Symlink module yang tidak dipublikasikan Motorola dari donor OPPO mt6896.
set -e

[ -d build/bazel_mgk_rules ] || { echo "ERROR: bukan workspace w1vo"; exit 1; }
[ -d kernel-6.12 ]           || { echo "ERROR: kernel-6.12 tidak ada"; exit 1; }

# --- 1. MODULE.bazel ---
# Root MODULE.bazel harus versi MGK, bukan bazel.MODULE.bazel AOSP:
# mgk.MODULE.bazel sudah include mgk_repo dan memakai mgk_kernel_toolchain_ext,
# jadi tidak bentrok dengan use_repo("kernel_toolchain_info") milik Kleaf.
MGK_MODULE=build/bazel_mgk_rules/bzlmod/mgk.MODULE.bazel
if [ -f "$MGK_MODULE" ]; then
  if [ -L MODULE.bazel ] || ! cmp -s MODULE.bazel "$MGK_MODULE"; then
    rm -f MODULE.bazel
    cp "$MGK_MODULE" MODULE.bazel
    echo "MODULE.bazel <- build/bazel_mgk_rules/bzlmod/mgk.MODULE.bazel"
  fi
else
  echo "WARNING: $MGK_MODULE tidak ada, MODULE.bazel dibiarkan"
fi

# --- 2. common-6.12 ---
[ -e common-6.12 ] || { ln -s kernel-6.12 common-6.12; echo "symlink common-6.12"; }

# --- 3. donor OPPO ---
DONOR=donor/oppo-mt6896/vendor/mediatek/kernel_modules
VM=vendor/mediatek/kernel_modules

if [ -d "$DONOR" ]; then
  link_donor() {
    rel="$1"
    [ -e "$DONOR/$rel" ] || { echo "  skip (tidak ada di donor): $rel"; return; }
    mkdir -p "$(dirname "$VM/$rel")"
    if [ -e "$VM/$rel" ] || [ -L "$VM/$rel" ]; then
      echo "  skip (sudah ada): $rel"; return
    fi
    src=$(realpath -m --relative-to="$(dirname "$VM/$rel")" "$DONOR/$rel")
    ln -s "$src" "$VM/$rel"
    echo "  link: $rel"
  }

  echo "Symlink module dari donor OPPO:"
  for m in \
      afs_common_utils \
      hbt_driver \
      hbt_driver_cus \
      met_drv_v3 \
      sched_cus \
      connectivity/common \
      connectivity/connfem \
      connectivity/fmradio \
      connectivity/gps \
      connectivity/wlan/adaptor \
      connectivity/wlan/core/gen4-mt79xx \
      connectivity/bt/linux_v2_ce \
      connectivity/bt/mt76xx ; do
    link_donor "$m"
  done
else
  echo "WARNING: donor/oppo-mt6896 tidak ada, skip symlink"
fi

# --- 4. parent vendor/mediatek (dipakai mgk_repo.MODULE.bazel path="../vendor/mediatek") ---
if [ ! -e ../vendor/mediatek ]; then
  mkdir -p ../vendor
  ln -sfn "$PWD/vendor/mediatek" ../vendor/mediatek
  echo "symlink ../vendor/mediatek -> $PWD/vendor/mediatek"
fi

echo
echo "Selesai. Cek:"
echo "  tail -3 MODULE.bazel"
echo "  ls -l common-6.12 tools/bazel"
echo "  ls -l $VM/afs_common_utils $VM/connectivity/common"

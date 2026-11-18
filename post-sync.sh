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
if [ -L MODULE.bazel ]; then
  echo "MODULE.bazel symlink -> file biasa + include MGK"
  rm MODULE.bazel
  cp build/kernel/kleaf/bzlmod/bazel.MODULE.bazel MODULE.bazel
fi
if ! grep -q 'bazel_mgk_rules/bzlmod:mgk_repo.MODULE.bazel' MODULE.bazel; then
  {
    echo ''
    echo '# MTK MGK'
    echo 'include("//build/bazel_mgk_rules/bzlmod:mgk_repo.MODULE.bazel")'
  } >> MODULE.bazel
  echo "include MGK ditambahkan ke MODULE.bazel"
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

echo
echo "Selesai. Cek:"
echo "  tail -3 MODULE.bazel"
echo "  ls -l common-6.12 tools/bazel"
echo "  ls -l $VM/afs_common_utils $VM/connectivity/common"

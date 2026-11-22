#!/bin/bash
# Siapkan workspace kernel X6871 (MT6895 / 6.12) setelah `repo sync`.
# Jalankan dari root workspace.
#
#   ./setup.sh
#
# Melakukan (idempotent, aman dijalankan berulang):
#   1. MODULE.bazel  <- mgk.MODULE.bazel (root AOSP tidak memuat MGK)
#   2. symlink common-6.12 -> kernel-6.12
#   3. symlink 13 module donor OPPO mt6896 (hanya bila workspace split legacy)
#   4. symlink ../vendor/mediatek (mgk_repo pakai path="../vendor/mediatek")
#   5. hapus label //vendor/... yang tidak tersedia dari mgk_64.bzl (bila masih ada)
set -e

die() { echo "ERROR: $*" >&2; exit 1; }

MGK_MODULE=build/bazel_mgk_rules/bzlmod/mgk.MODULE.bazel
F=kernel_device_modules-6.12/kernel/kleaf/mgk_64.bzl
VM=vendor/mediatek/kernel_modules
DONOR=donor/oppo-mt6896/vendor/mediatek/kernel_modules
[ -f "$MGK_MODULE" ] || die "$MGK_MODULE tidak ada; jalankan dari root workspace setelah repo sync"
[ -d kernel-6.12 ] || die "kernel-6.12 tidak ada"
[ -f "$F" ] || die "$F tidak ada"
[ -d "$VM" ] || [ -d "$DONOR" ] || die "$VM tidak ada"

# MGK resolves these from the workspace. Never silently use another checkout.
if [ -e ../vendor/mediatek ] || [ -L ../vendor/mediatek ]; then
  [ ../vendor/mediatek -ef vendor/mediatek ] || \
    die "../vendor/mediatek bukan milik workspace ini; gunakan workspace di bawah direktori induk terpisah"
fi
if [ -e common-6.12 ]; then
  [ common-6.12 -ef kernel-6.12 ] || die "common-6.12 tidak menunjuk ke kernel-6.12 workspace ini"
fi

# --- 1. MODULE.bazel -------------------------------------------------------
# Root MODULE.bazel harus versi MGK, bukan bazel.MODULE.bazel AOSP:
# mgk.MODULE.bazel sudah include mgk_repo + mgk_kernel_toolchain_ext,
# jadi tidak bentrok dengan use_repo("kernel_toolchain_info") milik Kleaf.
if [ -L MODULE.bazel ] || ! cmp -s MODULE.bazel "$MGK_MODULE"; then
  rm -f MODULE.bazel
  cp "$MGK_MODULE" MODULE.bazel
  echo "MODULE.bazel <- $MGK_MODULE"
fi

# --- 2. common-6.12 --------------------------------------------------------
[ -e common-6.12 ] || { ln -sfn kernel-6.12 common-6.12; echo "symlink common-6.12"; }

# --- 3. donor OPPO (fallback untuk workspace split legacy) -----------------
if [ -d "$VM/afs_common_utils" ] && [ ! -L "$VM/afs_common_utils" ]; then
  echo "vendor/mediatek/kernel_modules sudah terpadu (vendored), skip symlink donor OPPO"
elif [ -d "$DONOR" ]; then
  link_donor() {
    rel="$1"
    [ -e "$DONOR/$rel" ] || { echo "  skip (tidak ada di donor): $rel"; return; }
    if [ -e "$VM/$rel" ] || [ -L "$VM/$rel" ]; then return; fi
    mkdir -p "$(dirname "$VM/$rel")"
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
  echo "WARNING: donor/oppo-mt6896 tidak ada dan $VM belum lengkap, skip symlink"
fi

# --- 4. parent vendor/mediatek --------------------------------------------
if [ ! -e ../vendor/mediatek ]; then
  mkdir -p ../vendor
  ln -sfn "$PWD/vendor/mediatek" ../vendor/mediatek
  echo "symlink ../vendor/mediatek -> $PWD/vendor/mediatek"
fi

# --- 5. trim label yang tidak tersedia ------------------------------------
# 20 grup module tidak dipublikasikan Motorola dan tidak ada di donor OPPO.
# Kalau labelnya dibiarkan, Bazel gagal "no such package".
# Branch port x6871-android16-6.12 sudah bersih; langkah ini hanya mengubah
# mgk_64.bzl bila masih ada label tak tersedia (mis. baseline mtk-base-latest).
MODS='afs_core_cus|afs_core_int|cpufreq_cus|cpufreq_int|fpsgo_cus|fpsgo_int|game_cus|game_int|gpio_sap_ctrl|met_drv_secure_v3|msync2_frd_cus|msync2_frd_int|mtk_input|perf_common_cus|perf_common_int|sched_int|task_turbo_cus|task_turbo_int|thinmd_exception|wwan'

if grep -qE "//vendor/mediatek/kernel_modules/($MODS)([/:])" "$F"; then
  [ -f "$F.orig" ] || cp "$F" "$F.orig"
  before=$(wc -l < "$F")
  grep -vE "//vendor/mediatek/kernel_modules/($MODS)([/:])" "$F" > "$F.new"
  mv "$F.new" "$F"
  after=$(wc -l < "$F")
  echo "mgk_64.bzl: $before -> $after baris (hapus $((before-after)) label)"
else
  echo "mgk_64.bzl: sudah bersih (0 label tak tersedia)"
fi

echo
echo 'Selesai. Lanjut:  ./build.sh user  (default OVERLAYS="entry_level_legacy.config X6871.config")'

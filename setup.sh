#!/bin/bash
# Siapkan workspace kernel X6871 (MT6895 / 6.12 atau 6.18) setelah `repo sync`.
# Jalankan dari root workspace.
#
#   ./setup.sh                 # KVER=6.12 (default, produksi)
#   KVER=6.18 ./setup.sh       # profil PLAN-6.18, GKI di path bawaan `common`
#
# Melakukan (idempotent, aman dijalankan berulang):
#   1. MODULE.bazel  <- mgk.MODULE.bazel (root AOSP tidak memuat MGK)
#   2. symlink common-<KVER> -> GKI (kernel-6.12 atau common)
#   3. symlink 13 module donor OPPO mt6896 (hanya bila workspace split legacy)
#   4. symlink ../vendor/mediatek (mgk_repo pakai path="../vendor/mediatek")
#   5. hapus label //vendor/... yang tidak tersedia dari mgk_64.bzl (bila masih ada)
#   6. patch Kleaf/MGK sesuai profil (multi-abi KMI 7 atau 6.18)
set -e

die() { echo "ERROR: $*" >&2; exit 1; }

KVER=${KVER:-6.12}
TREE=kernel_device_modules-$KVER
if [ "$KVER" = "6.12" ]; then
  GKI_DIR=kernel-6.12
else
  GKI_DIR=common
fi

MGK_MODULE=build/bazel_mgk_rules/bzlmod/mgk.MODULE.bazel
F=$TREE/kernel/kleaf/mgk_64.bzl
VM=vendor/mediatek/kernel_modules
DONOR=donor/oppo-mt6896/vendor/mediatek/kernel_modules
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
[ -f "$MGK_MODULE" ] || die "$MGK_MODULE tidak ada; jalankan dari root workspace setelah repo sync"
[ -d "$GKI_DIR" ] || die "$GKI_DIR tidak ada (KVER=$KVER)"
[ -f "$F" ] || die "$F tidak ada"
[ -d "$VM" ] || [ -d "$DONOR" ] || die "$VM tidak ada"

# MGK resolves these from the workspace. Never silently use another checkout.
if [ -e ../vendor/mediatek ] || [ -L ../vendor/mediatek ]; then
  [ ../vendor/mediatek -ef vendor/mediatek ] || \
    die "../vendor/mediatek bukan milik workspace ini; gunakan workspace di bawah direktori induk terpisah"
fi
if [ -e common-$KVER ]; then
  [ common-$KVER -ef "$GKI_DIR" ] || die "common-$KVER tidak menunjuk ke $GKI_DIR workspace ini"
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

# --- 2. common-<KVER> ------------------------------------------------------
[ -e common-$KVER ] || { ln -sfn "$GKI_DIR" common-$KVER; echo "symlink common-$KVER -> $GKI_DIR"; }

# --- 2b. Bazel 8: banyak glob lama memang kosong ---------------------------
if [ "$KVER" = "6.18" ]; then
  touch device.bazelrc
  if ! grep -q 'incompatible_disallow_empty_glob=false' device.bazelrc; then
    printf 'common --incompatible_disallow_empty_glob=false\n' >> device.bazelrc
    echo 'device.bazelrc: allow empty glob (Bazel 8)'
  fi
fi

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

# --- 6. patch profil -------------------------------------------------------
if [ "$KVER" = "6.18" ]; then
  MGK_PATCH=$HERE/patches/bazel_mgk_rules-6.18.patch
  [ -f "$MGK_PATCH" ] || die "$MGK_PATCH tidak ada"
  if git -C build/bazel_mgk_rules apply --reverse --check "$MGK_PATCH" 2>/dev/null; then
    echo 'bazel_mgk_rules: patch 6.18 sudah terpasang'
  elif git -C build/bazel_mgk_rules apply --check "$MGK_PATCH"; then
    git -C build/bazel_mgk_rules apply "$MGK_PATCH"
    echo 'bazel_mgk_rules: patch 6.18 terpasang'
  else
    die 'patch bazel_mgk_rules-6.18 tidak dapat diterapkan; cek revisi dan perubahan lokal'
  fi
  # Root MODULE.bazel harus memakai versi yang sudah dipatch (deps main-kernel-2026).
  cp "$MGK_MODULE" MODULE.bazel

  SUFFIX_PATCH=$HERE/patches/kleaf-localversion-suffix.patch
  [ -f "$SUFFIX_PATCH" ] || die "$SUFFIX_PATCH tidak ada"
  if git -C build/kernel apply --reverse --check "$SUFFIX_PATCH" 2>/dev/null; then
    echo 'Kleaf: patch LOCALVERSION_SUFFIX sudah terpasang'
  elif git -C build/kernel apply --check "$SUFFIX_PATCH"; then
    git -C build/kernel apply "$SUFFIX_PATCH"
    echo 'Kleaf: patch LOCALVERSION_SUFFIX terpasang'
  else
    die 'patch kleaf-localversion-suffix tidak dapat diterapkan; cek perubahan lokal build/kernel'
  fi

  # Profil uji 6.18-lts (17b8bfe5ce75): patch bug blk_finish_plug/blk_plug_invalidate_ts
  # via git am agar common tetap bersih (tanpa -dirty). Dihapus saat upstream fix masuk.
  COMMON_LTS_PATCH=$HERE/patches/common-6.18-blk-plug-invalidate-ts.patch
  [ -f "$COMMON_LTS_PATCH" ] || die "$COMMON_LTS_PATCH tidak ada"
  if git -C common apply --reverse --check "$COMMON_LTS_PATCH" 2>/dev/null; then
    echo 'common: patch blk_plug_invalidate_ts sudah terpasang'
  elif [ "$(git -C common rev-parse HEAD 2>/dev/null)" = 17b8bfe5ce7568445def263dc609f839f3b469f6 ]; then
    git -C common -c core.hooksPath=/dev/null \
      -c user.name="Rama Bondan Prakoso" -c user.email="ramanarubp@gmail.com" \
      am --committer-date-is-author-date "$COMMON_LTS_PATCH"
    echo 'common: patch blk_plug_invalidate_ts terpasang (git am)'
  fi
else
  # GKI 14d405822690 memuat target ABI yang belum tersedia di Kleaf Motorola.
  # Backport hanya rule build; jangan mengubah kernel-6.12.
  if [ "$(git -C kernel-6.12 rev-parse HEAD 2>/dev/null)" = 14d40582269013a9bc6df12b2479da18f27e3d33 ]; then
    KLEAF_PATCH=$HERE/patches/kleaf-multi-abi-update.patch
    if git -C build/kernel apply --reverse --check "$KLEAF_PATCH" 2>/dev/null; then
      echo 'Kleaf: backport multi_abi_update sudah terpasang'
    elif git -C build/kernel apply --check "$KLEAF_PATCH"; then
      git -C build/kernel apply "$KLEAF_PATCH"
      echo 'Kleaf: backport multi_abi_update terpasang'
    else
      die 'backport multi_abi_update tidak dapat diterapkan; cek revisi dan perubahan lokal build/kernel'
    fi
  fi
fi

echo
if [ "$KVER" = "6.18" ]; then
  echo 'Selesai. Lanjut:  KVER=6.18 ./build.sh user'
else
  echo 'Selesai. Lanjut:  ./build.sh user  (default OVERLAYS="entry_level_legacy.config X6871.config")'
fi

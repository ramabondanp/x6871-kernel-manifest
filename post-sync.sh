#!/bin/bash
# Jalankan dari root workspace setelah `repo sync`.
# 1. Tambah include MGK ke MODULE.bazel (AOSP linkfile belum memuatnya).
# 2. Buat symlink common-6.12 -> kernel-6.12 (dipakai mgk.bzl untuk build "ack").
set -e

[ -d build/bazel_mgk_rules ] || { echo "ERROR: bukan workspace w1vo"; exit 1; }
[ -d kernel-6.12 ]           || { echo "ERROR: kernel-6.12 tidak ada"; exit 1; }

# --- MODULE.bazel ---
if [ -L MODULE.bazel ]; then
  echo "MODULE.bazel adalah symlink, ganti dengan file biasa + include MGK"
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

# --- common-6.12 ---
if [ ! -e common-6.12 ]; then
  ln -s kernel-6.12 common-6.12
  echo "symlink common-6.12 -> kernel-6.12 dibuat"
fi

echo
echo "Selesai. Cek:"
echo "  cat MODULE.bazel | tail -3"
echo "  ls -l common-6.12 tools/bazel"

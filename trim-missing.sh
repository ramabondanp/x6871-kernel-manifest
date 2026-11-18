#!/bin/bash
# Hapus label //vendor/mediatek/kernel_modules/<modul> yang tidak tersedia
# (tidak ada di repo w1vo maupun donor OPPO) dari kernel/kleaf/mgk_64.bzl.
#
# Jalankan dari root workspace, setelah post-sync.sh.
# Backup otomatis ke mgk_64.bzl.orig
set -e

F=kernel_device_modules-6.12/kernel/kleaf/mgk_64.bzl
[ -f "$F" ] || { echo "ERROR: $F tidak ada"; exit 1; }

# Modul yang tidak ada di: 11 repo w1vo + donor oppo-mt6896
MODS='afs_core_cus|afs_core_int|cpufreq_cus|cpufreq_int|fpsgo_cus|fpsgo_int|game_cus|game_int|gpio_sap_ctrl|met_drv_secure_v3|msync2_frd_cus|msync2_frd_int|mtk_input|perf_common_cus|perf_common_int|sched_int|task_turbo_cus|task_turbo_int|thinmd_exception|wwan'

[ -f "$F.orig" ] || cp "$F" "$F.orig"

before=$(wc -l < "$F")
grep -vE "//vendor/mediatek/kernel_modules/($MODS)([/:])" "$F" > "$F.new"
mv "$F.new" "$F"
after=$(wc -l < "$F")

echo "mgk_64.bzl : $before -> $after baris (hapus $((before-after)))"
echo "backup     : $F.orig"
echo
echo "Sisa referensi:"
grep -cE "//vendor/mediatek/kernel_modules/($MODS)([/:])" "$F" || true

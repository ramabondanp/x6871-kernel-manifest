#!/bin/bash
# Pasang tc_common_class ke tree w1vo.
# Jalankan dari root workspace. Lihat PLAN.md §8.
#
#   ./add-tc-common-class.sh /path/ke/transsion-kernel_device_modules-6.1
#
# Kenapa modul ini
# ----------------
# Nama modul `tc_common_class`, nama file `tc_common_class.c` -- tapi maknanya
# jauh lebih besar dari namanya. Di firmware X6871, 19 modul bergantung pada
# `tran_device_register` / `tran_get_by_name` yang HANYA disediakan di sini:
#
#   mt6375-battery, mtk_battery_manager, rt6160-regulator, tc_ambient_temp_det,
#   tc_audio, tc_charger_framework, tc_gauge, tc_lcd_notify, tc_misc_intf,
#   tc_otg_ctrl, tc_phy_insert_det, tc_pid_chg_algo, tc_pmic, tc_tcpc,
#   tc_temp_forecast, tc_trancare, tc_water_detect, tran_charge_transfer,
#   tran_usb_ctrl
#
# Ini juga yang membuat `mtk_battery_manager.ko` versi vendor bisa jalan:
# .ko itu mengimpor `tc_is_si_battery` / `tc_is_support_charge_transfer`
# (dari tc_misc_intf) -- bukan API MTK.
#
# Sifatnya ADITIF, bukan fork: tree w1vo belum punya `struct tran_device`
# sama sekali, jadi tidak ada simbol yang bertabrakan.
#
# Bukti kecocokan (bukan tebakan):
#   epxorts/impor .ko firmware vs hasil build -> 8/8 dan 23/23, nol selisih.
#
# Sumber (GPL-2.0):
#   https://github.com/ramabondanp/transsion-kernel_device_modules-6.1
#   branch: android15-split
#   path  : drivers/power/supply/transsion/tc_common_class.{c,h}
#
# Patch 6.12 yang diperlukan (2):
#   1. header memakai #if IS_ENABLED(CONFIG_TC_CLASS_SUPPORT). Config itu tidak
#      ada di tree kita, sehingga header jatuh ke `static inline` fallback dan
#      bertabrakan dengan definisi di .c (redefinition). Diaktifkan lewat
#      copts = ["-DCONFIG_TC_CLASS_SUPPORT=1"].
#   2. class_create(THIS_MODULE, "x") -> class_create("x")  (6.12 buang arg owner)
#
# Idempotent.
set -e

SRC=${1:?pakai: ./add-tc-common-class.sh /path/ke/transsion-kernel_device_modules-6.1}
T=kernel_device_modules-6.12
D=$T/drivers/power/supply/transsion
S=$SRC/drivers/power/supply/transsion

[ -f "$S/tc_common_class.c" ] || { echo "ERROR: $S/tc_common_class.c tidak ada"; exit 1; }
[ -d "$T/drivers/power/supply" ] || { echo "ERROR: jalankan dari root workspace w1vo"; exit 1; }

mkdir -p "$D"
cp "$S/tc_common_class.c" "$S/tc_common_class.h" "$D/"

python3 - "$D/tc_common_class.c" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'tran_class = class_create(THIS_MODULE, "tran_class");'
new = 'tran_class = class_create("tran_class");'
if old in s:
    s = s.replace(old, new, 1)
    open(p, 'w').write(s)
    print("  class_create: API 6.12 (1 argumen)")
else:
    print("  class_create: sudah disesuaikan")
PY

python3 - "$T/drivers/power/supply/BUILD.bazel" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if 'name = "tc_common_class"' in s:
    print("  BUILD.bazel: sudah terdaftar")
else:
    anchor = 'define_mgk_ddk_ko(\n    name = "charger_class",'
    assert anchor in s, "anchor charger_class tidak ditemukan"
    block = '''define_mgk_ddk_ko(
    name = "tc_common_class",
    srcs = [
        "transsion/tc_common_class.c",
    ],
    hdrs = [
        "transsion/tc_common_class.h",
    ],
    includes = [
        ".",
        "transsion",
    ],
    # Aktifkan blok extern di tc_common_class.h. Tanpa ini header memakai
    # static inline fallback yang bertabrakan dengan definisi di .c
    # (redefinition). Di tree Transsion config ini hidup via Kconfig.
    copts = ["-DCONFIG_TC_CLASS_SUPPORT=1"],
)

'''
    s = s.replace(anchor, block + anchor, 1)
    open(p, 'w').write(s)
    print("  BUILD.bazel: terdaftar")
PY

python3 - "$T" <<'PY'
import sys
p = sys.argv[1] + '/kernel/kleaf/mgk_64.bzl'
s = open(p).read()
if 'power/supply:tc_common_class' in s:
    print("  mgk_64.bzl: sudah terdaftar")
else:
    a = '    "//kernel_device_modules-{}/drivers/power/supply:charger_class".format(kernel_version),\n'
    assert a in s, "anchor charger_class tidak ditemukan di mgk_64.bzl"
    s = s.replace(a, a + '    "//kernel_device_modules-{}/drivers/power/supply:tc_common_class".format(kernel_version),\n', 1)
    open(p, 'w').write(s)
    print("  mgk_64.bzl: terdaftar")
PY

echo
echo "Selesai. Build:"
echo "  OVERLAYS=entry_level_legacy.config ./build.sh user"
echo
echo "Verifikasi (ekspor harus 8, impor 23 -- sama dengan firmware):"
echo "  readelf -sW .../tc_common_class.ko | awk '\$7!=\"UND\" && \$4==\"FUNC\"'"
echo "  modinfo -F description .../tc_common_class.ko   # Switching Charger Class Device"

#!/bin/bash
# [HISTORIS — sudah ter-commit di alps-kernel_device_modules-6.12 branch x6871-android16-6.12]
# Pasang fondasi charger Transsion: tc_charger_class, tc_adapter_class,
# tc_algorithm_class, tc_misc_intf (+ tc_common_class dari script lain).
# Jalankan dari root workspace. Lihat docs/PLAN.md §6.2d.
#
#   ./scripts/add-tc-charger-stack.sh /path/ke/transsion-kernel_device_modules-6.1
#
# Kenapa 4 modul ini satu paket
# -----------------------------
# tc_misc_intf TIDAK standalone. Di firmware X6871 ia mengimpor:
#   get_charger_by_name, charger_dev_get_{adc,vbus,ibus}  -> tc_charger_class
#   get_tadapter_by_name, tadapter_dev_get_property       -> tc_adapter_class
#   get_tchg_alg_by_name, tchg_alg_get/set_prop           -> tc_algorithm_class
#
# Dan tc_charger_class di firmware MENGGANTIKAN charger_class MTK:
#   - firmware TIDAK mengirim charger_class.ko
#   - tc_charger_class.ko mendefinisikan 115 simbol charger_dev_* (bukan impor)
#   - 80 simbol berkolisi dengan charger_class MTK
# Jadi memasang ini = ganti fondasi charger, bukan tambahan.
#
# Yang TIDAK bisa disalin dari source 6.1 (Transsion hanya merilis 6.1):
#   8 ekspor tc_misc_intf  (tc_is_si_battery, tc_is_support_*, ...)
#   5 ekspor tc_charger_class (charger_dev_need_hz_ctrl, ...)
# Script ini mengisi yang tc_misc_intf lewat rekonstruksi dari .ko; sisanya
# ditandai di PLAN.md.
#
# Patch 6.12 yang diperlukan:
#   1. class_create(THIS_MODULE, "x") -> class_create("x")   (3 file)
#   2. const char *const f(...)       -> const char *f(...)  (Wignored-qualifiers)
#   3. platform remove: int -> void, buang `return 0;`
#   4. tc_misc_intf.h needs full transitive header chain
#   5. ko_deps: 4 modul tc_* + mtprof:bootprof (mt_boot_finish)
#
# Idempotent.
set -e

SRC=${1:?pakai: ./add-tc-charger-stack.sh /path/ke/transsion-kernel_device_modules-6.1}
HERE=$(cd "$(dirname "$0")" && pwd)
T=kernel_device_modules-6.12
D=$T/drivers/power/supply/transsion
S=$SRC/drivers/power/supply/transsion

[ -f "$S/tc_charger_class.c" ] || { echo "ERROR: source 6.1 tidak ditemukan di $S"; exit 1; }
[ -d "$T/drivers/power/supply" ] || { echo "ERROR: jalankan dari root workspace w1vo"; exit 1; }

mkdir -p "$D"
cp "$S/tc_charger_class.c" "$S/tc_charger_class.h" \
   "$S/tc_adapter_class.c" "$S/tc_adapter_class.h" \
   "$S/tc_algorithm_class.c" "$S/tc_algorithm_class.h" \
   "$S/tc_misc_intf.c" "$S/tc_misc_intf.h" \
   "$S/tc_charger.h" "$S/tc_voter.h" "$S/tc_tcpc.h" "$S/tc_gauge.h" "$D/"

python3 - "$D" <<'PY'
import re, sys
D = sys.argv[1]

# 1. class_create
for f in ('tc_adapter_class.c', 'tc_algorithm_class.c', 'tc_charger_class.c'):
    p = f'{D}/{f}'
    s = open(p).read()
    s2, n = re.subn(r'class_create\(THIS_MODULE,\s*', 'class_create(', s)
    if n:
        open(p, 'w').write(s2)
print("  class_create: API 6.12")

# 2. const qualifier pada return type
p = f'{D}/tc_algorithm_class.h'
s = open(p).read()
s = s.replace('extern const char *const tchg_alg_notify_evt_tostring(',
              'extern const char *tchg_alg_notify_evt_tostring(')
open(p, 'w').write(s)
p = f'{D}/tc_algorithm_class.c'
s = open(p).read()
s = s.replace('extern const char *const\ntchg_alg_notify_evt_tostring(',
              'extern const char *\ntchg_alg_notify_evt_tostring(')
open(p, 'w').write(s)

p = f'{D}/tc_tcpc.h'
s = open(p).read()
s = s.replace('extern const char *const tc_pd_type_tostring(',
              'extern const char *tc_pd_type_tostring(')
open(p, 'w').write(s)
print("  const qualifier: dibuang")

# 3. platform remove -> void
p = f'{D}/tc_misc_intf.c'
s = open(p).read()
s = s.replace('static int tc_misc_remove(struct platform_device *dev)',
              'static void tc_misc_remove(struct platform_device *dev)')
s = s.replace('''static void tc_misc_remove(struct platform_device *dev)
{

	return 0;
}''', '''static void tc_misc_remove(struct platform_device *dev)
{
}''')
open(p, 'w').write(s)
print("  platform remove: void")
PY

# 4. tc_misc_intf: field support_si_bat + parse_dt
python3 - "$D/tc_misc_intf.c" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''	bool det_vbus_by_dvchg;
	bool det_ibus_by_swchg;
	bool det_tusb_by_swchg;
};'''
new = '''	bool det_vbus_by_dvchg;
	bool det_ibus_by_swchg;
	bool det_tusb_by_swchg;
	/* Dibaca tc_misc_parse_dt(); dipakai tc_is_si_battery() (6.12). */
	bool support_si_bat;
};'''
if 'support_si_bat;' not in s:
    assert old in s
    s = s.replace(old, new, 1)
old2 = '''	info->det_vbus_by_dvchg = of_property_read_bool(np, "det_vbus_by_dvchg");'''
new2 = '''	info->support_si_bat = of_property_read_bool(np, "support_si_bat");
	info->det_vbus_by_dvchg = of_property_read_bool(np, "det_vbus_by_dvchg");'''
if 'of_property_read_bool(np, "support_si_bat")' not in s:
    assert old2 in s
    s = s.replace(old2, new2, 1)
open(p, 'w').write(s)
print("  support_si_bat: ditambahkan")
PY

# 4b. Sisipkan 8 fungsi tambahan 6.12 (rekonstruksi dari `.ko` X6871).
#     Transsion hanya merilis source 6.1; fungsi ini tidak akan pernah ada di
#     source. Alasan & bukti ada di patches/tc_misc_intf_6_12_extra.c.
"$HERE/patch-tc-misc-6.12.sh" "$D"

# 5. BUILD.bazel
python3 - "$T/drivers/power/supply/BUILD.bazel" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if 'name = "tc_charger_class"' in s:
    print("  BUILD.bazel: sudah terdaftar")
    raise SystemExit
block = ''
for mod in ('tc_algorithm_class', 'tc_adapter_class', 'tc_charger_class'):
    block += f'''define_mgk_ddk_ko(
    name = "{mod}",
    srcs = [
        "transsion/{mod}.c",
    ],
    hdrs = [
        "transsion/{mod}.h",
    ],
    includes = [
        ".",
        "transsion",
    ],
    copts = ["-DCONFIG_TC_CLASS_SUPPORT=1"],
)

'''
block += '''define_mgk_ddk_ko(
    name = "tc_misc_intf",
    srcs = [
        "transsion/tc_misc_intf.c",
    ],
    hdrs = [
        "transsion/tc_misc_intf.h",
        "transsion/tc_charger.h",
        "transsion/tc_voter.h",
        "transsion/tc_tcpc.h",
        "transsion/tc_gauge.h",
        "transsion/tc_charger_class.h",
        "transsion/tc_adapter_class.h",
        "transsion/tc_algorithm_class.h",
        "transsion/tc_common_class.h",
    ],
    includes = [
        ".",
        "transsion",
    ],
    ko_deps = [
        ":tc_algorithm_class",
        ":tc_adapter_class",
        ":tc_charger_class",
        ":tc_common_class",
        "//kernel_device_modules-{}/drivers/misc/mediatek/mtprof:bootprof".format(kernel_version),
    ],
)

'''
anchor = 'define_mgk_ddk_ko(\n    name = "tc_common_class",'
assert anchor in s
s = s.replace(anchor, block + anchor, 1)
open(p, 'w').write(s)
print("  BUILD.bazel: 4 modul terdaftar")
PY

# 6. mgk_64.bzl
python3 - "$T" <<'PY'
import sys
p = sys.argv[1] + '/kernel/kleaf/mgk_64.bzl'
s = open(p).read()
anchor = '    "//kernel_device_modules-{}/drivers/power/supply:tc_common_class".format(kernel_version),\n'
assert anchor in s
add = ''
for mod in ('tc_algorithm_class', 'tc_adapter_class', 'tc_charger_class', 'tc_misc_intf'):
    tag = f'drivers/power/supply:{mod}'
    if tag not in s:
        add += f'    "//kernel_device_modules-{{}}/drivers/power/supply:{mod}".format(kernel_version),\n'
if not add:
    print("  mgk_64.bzl: sudah terdaftar")
else:
    s = s.replace(anchor, anchor + add, 1)
    open(p, 'w').write(s)
    print(f"  mgk_64.bzl: {len(add.splitlines())} modul terdaftar")
PY

echo
echo "Selesai. Build:"
echo "  OVERLAYS=entry_level_legacy.config ./build.sh user"
echo
echo "Verifikasi isi vs firmware (target: ekspor IDENTIK):"
echo "  readelf -sW .../tc_misc_intf.ko | awk '\$7!=\"UND\" && \$4==\"GLOBAL\"'"
echo
echo "CATATAN: 8 ekspor tc_misc_intf dan 5 ekspor tc_charger_class adalah"
echo "tambahan 6.12 yang tidak ada di source. Lihat PLAN.md §6.2d."

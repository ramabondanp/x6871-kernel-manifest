#!/bin/bash
# Pasang 8 fungsi tambahan 6.12 ke tc_misc_intf.
# Dipanggil oleh add-tc-charger-stack.sh; bisa juga dipanggil langsung.
#
#   ./patch-tc-misc-6.12.sh kernel_device_modules-6.12/drivers/power/supply/transsion
#
# Kenapa perlu alat terpisah
# -------------------------
# Transsion hanya merilis source kernel 6.1. `tc_misc_intf.ko` versi X6871
# (kernel 6.12) mengekspor 8 fungsi yang tidak ada di source 6.1:
#
#   tc_is_dts_node_available   tc_is_si_battery
#   tc_is_support_charge_transfer   tc_is_support_battery_manager
#   tc_is_support_temp_forecast     tc_is_support_adapter_control
#   tc_is_support_otg_ctrl      tc_get_battery_id
#
# Fungsi-fungsi ini TIDAK akan pernah muncul di source. Isinya direkonstruksi
# dari `.ko` firmware (bukan tebakan). Bukti ada di komentar
# patches/tc_misc_intf_6_12_extra.c:
#   - pola seragam, terverifikasi per-fungsi di disassembly
#   - `dtsi_check_fea_list` (5 entri) dipulihkan dari relokasi ABS64
#   - enum TRAN_PROP_BATTERY_ID = 49 cocok (`mov w1, #0x32`)
#
# Idempotent.
set -e

D=${1:?pakai: ./patch-tc-misc-6.12.sh <dir-transsion>}
HERE=$(cd "$(dirname "$0")" && pwd)
EXTRA=$HERE/patches/tc_misc_intf_6_12_extra.c

[ -f "$EXTRA" ] || { echo "ERROR: $EXTRA tidak ada"; exit 1; }
[ -f "$D/tc_misc_intf.c" ] || { echo "ERROR: jalankan add-tc-charger-stack.sh dulu"; exit 1; }

python3 - "$D/tc_misc_intf.c" "$EXTRA" <<'PY'
import sys

dst, extra = sys.argv[1], sys.argv[2]
s = open(dst).read()
block = open(extra).read()

if 'tc_is_support_charge_transfer' in s:
    print("  fungsi 6.12: sudah ada")
    raise SystemExit

anchor = 'static int __init tran_class_init(void)'
assert anchor in s, "anchor tran_class_init tidak ditemukan"
s = s.replace(anchor, block.rstrip() + '\n\n' + anchor, 1)
open(dst, 'w').write(s)

h = dst[:-2] + '.h'
hs = open(h).read()
if 'tc_is_si_battery' not in hs:
    decls = """
/* Tambahan 6.12 -- direkonstruksi dari .ko X6871, lihat catatan di .c */
extern bool tc_is_dts_node_available(struct device_node *np);
extern bool tc_is_si_battery(void);
extern bool tc_is_support_charge_transfer(void);
extern bool tc_is_support_battery_manager(void);
extern bool tc_is_support_temp_forecast(void);
extern bool tc_is_support_adapter_control(void);
extern bool tc_is_support_otg_ctrl(void);
extern int tc_get_battery_id(void);

"""
    k = hs.rfind('#endif')
    hs = hs[:k] + decls + hs[k:]
    open(h, 'w').write(hs)

print("  fungsi 6.12: 8 fungsi disisipkan")
PY

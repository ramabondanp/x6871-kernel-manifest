#!/bin/bash
# Pasang driver regulator tran_ldo (ET5904) ke tree w1vo.
# Jalankan dari root workspace. Lihat PLAN.md §6.2.
#
#   ./add-tran-ldo.sh /path/ke/et5904.c
#
# Kenapa perlu:
#   DT X6871 punya `dvdd-supply = <&TRANLDO26>` di node panel1@0.
#   TRANLDO26 disediakan tran_ldo. Tanpa modul ini, DVDD panel tidak pernah
#   menyala dan layar tidak akan hidup.
#
# Sumber (GPL-2.0):
#   https://github.com/ramabondanp/transsion-kernel_device_modules-6.1
#   branch: android15-split
#   path  : drivers/regulator/et5904.c
#   ambil: curl -sSLO https://raw.githubusercontent.com/ramabondanp/\
#           transsion-kernel_device_modules-6.1/android15-split/\
#           drivers/regulator/et5904.c
#
# Kenapa et5904.c dan bukan RE:
#   - kompatibel string di firmware `tran,tran_ldo`, source `tran,et5904`
#   - keduanya punya my_regulator_enable_regmap + discharge RDIS yang sama
#   - pola nama: source "ET5904LDO"#num#i2cid  ==  firmware TRANLDO%d%d
#   - et5904_regulators6[] = LDO 1..4 di i2c bus 6
#     -> TRANLDO16/26/36/46  == persis node DT X6871
#   - rentang tegangan cocok DT: VIND 600k..1.8M, VINA 1.2M..3.3M
#
# Idempotent.
set -e

SRC=${1:?pakai: ./add-tran-ldo.sh /path/ke/et5904.c}
T=kernel_device_modules-6.12
R=$T/drivers/regulator

[ -f "$SRC" ] || { echo "ERROR: $SRC tidak ada"; exit 1; }
[ -d "$R" ] || { echo "ERROR: jalankan dari root workspace w1vo"; exit 1; }

python3 - "$SRC" "$R/tran_ldo.c" <<'PY'
import sys
src = open(sys.argv[1]).read()
out = sys.argv[2]

# 1. prefix nama regulator: ET5904LDO -> TRANLDO
src = src.replace('ET5904LDO', 'TRANLDO')

# 2. identitas modul
src = src.replace('"tran,et5904"', '"tran,tran_ldo"')
src = src.replace('{ "et5904", }', '{ "tran_ldo", }')
src = src.replace('.name = "et5904",', '.name = "tran_ldo",')
src = src.replace('MODULE_DESCRIPTION("ET5904 PMIC voltage regulator driver");',
                  'MODULE_DESCRIPTION("Tran 4LDO  driver");')

# 3. probe: 6.12 tidak lagi meneruskan i2c_device_id
src = src.replace('''static int et5904_i2c_probe(struct i2c_client *i2c,
			     const struct i2c_device_id *id)
{''', '''static int et5904_i2c_probe(struct i2c_client *i2c)
{''')

# 4. Guard IS_ENABLED(TRAN_AD10) / TRAN_AE10 / CONFIG_TRAN_DUAL_INTERNAL_TEMP_PATCH
#    dibiarkan apa adanya: ketiganya tidak didefinisikan di tree w1vo, jadi
#    IS_ENABLED() bernilai 0 dan bloknya otomatis tidak dikompilasi. Blok itu
#    memanggil regulator_init_complete_mainlcm() yang tidak ada di tree kita.

open(out, 'w').write(src)
print("  tran_ldo.c ditulis:", len(src.splitlines()), "baris")
PY

# 5. daftarkan di BUILD.bazel (SIMPLE_MODULE_NAME)
python3 - "$R" <<'PY'
import sys
p = sys.argv[1] + '/BUILD.bazel'
s = open(p).read()
if '"tran_ldo"' in s:
    print("  BUILD.bazel: sudah terdaftar")
else:
    a = '    "wl2868c-regulator",\n'
    assert a in s, "anchor SIMPLE_MODULE_NAME tidak ditemukan"
    s = s.replace(a, a + '    "tran_ldo",\n', 1)
    open(p, 'w').write(s)
    print("  BUILD.bazel: masuk SIMPLE_MODULE_NAME")
PY

# 6. daftarkan di mgk_64.bzl
python3 - "$T" <<'PY'
import sys, re
p = sys.argv[1] + '/kernel/kleaf/mgk_64.bzl'
s = open(p).read()
if 'regulator:tran_ldo' in s:
    print("  mgk_64.bzl: sudah terdaftar")
else:
    m = re.search(r'    "//kernel_device_modules-\{\}/drivers/regulator:[a-z0-9-]+"\.format\(kernel_version\),\n', s)
    assert m, "anchor regulator tidak ditemukan"
    s = s.replace(m.group(0), m.group(0) +
                  '    "//kernel_device_modules-{}/drivers/regulator:tran_ldo".format(kernel_version),\n', 1)
    open(p, 'w').write(s)
    print("  mgk_64.bzl: terdaftar")
PY

echo
echo "Selesai. Build:"
echo "  OVERLAYS=entry_level_legacy.config ./build.sh user"
echo
echo "Verifikasi (harus muncul TRANLDO16/26/36/46):"
echo "  strings .../tran_ldo.ko | grep -oE 'TRANLDO[0-9]+' | sort -u"
echo "  modinfo -F alias .../tran_ldo.ko   # of:N*T*Ctran,tran_ldo"

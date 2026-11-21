#!/bin/bash
# Port driver kamera Infinix X6871 (4 sensor + camera_eeprom_v4l2) ke
# vendor/mediatek/kernel_modules/mtkcam dari donor mt6897 6.1.
# Jalankan dari root workspace w1vo, setelah `setup.sh`.
#
#   ./add-camera-x6871.sh /path/ke/mt6897-extract
#
# Idempotent: aman dijalankan berulang.
set -e

SRC=${1:?pakai: ./add-camera-x6871.sh /path/ke/mt6897-extract}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
D=$SRC/vendor/mediatek/kernel_modules/mtkcam/imgsensor/src-v4l2/common
T=vendor/mediatek/kernel_modules/mtkcam
T_COMMON=$T/imgsensor/src-v4l2/common

[ -d "$D/s5khm6sx_mipi_raw" ] || { echo "ERROR: $D tidak lengkap."; exit 1; }
[ -d "$T_COMMON" ] || { echo "ERROR: jalankan dari root workspace w1vo"; exit 1; }

for s in s5khm6sx_mipi_raw gc32e1_mipi_raw gc02m3macro_mipi_raw; do
    echo "== $s"
    rm -rf "$T_COMMON/$s"
    cp -a "$D/$s" "$T_COMMON/$s"
    sed -i 's/\r$//' "$T_COMMON/$s"/*
done

# Buat static agar tidak bentrok simbol antar-subdriver
sed -i 's/^int tran_get_imgsensor_id/static int tran_get_imgsensor_id/' \
    "$T_COMMON/s5khm6sx_mipi_raw/s5khm6sxmipiraw_Sensor.c" \
    "$T_COMMON/gc02m3macro_mipi_raw/gc02m3macromipiraw_Sensor.c"

echo "== gc02m3_mipi_raw (turunan gc02m3macro, sensor_id 0x0202, mask 0xFFFC == 0x0200)"
rm -rf "$T_COMMON/gc02m3_mipi_raw"
mkdir -p "$T_COMMON/gc02m3_mipi_raw"
cp "$T_COMMON/gc02m3macro_mipi_raw/gc02m3macro_ana_gain_table.h" "$T_COMMON/gc02m3_mipi_raw/gc02m3_ana_gain_table.h"
cp "$T_COMMON/gc02m3macro_mipi_raw/gc02m3macro_Sensor_setting.h" "$T_COMMON/gc02m3_mipi_raw/gc02m3_Sensor_setting.h"
cp "$T_COMMON/gc02m3macro_mipi_raw/gc02m3macromipiraw_Sensor.h" "$T_COMMON/gc02m3_mipi_raw/gc02m3mipiraw_Sensor.h"
cp "$T_COMMON/gc02m3macro_mipi_raw/gc02m3macromipiraw_Sensor.c" "$T_COMMON/gc02m3_mipi_raw/gc02m3mipiraw_Sensor.c"
cp "$T_COMMON/gc02m3macro_mipi_raw/Makefile" "$T_COMMON/gc02m3_mipi_raw/Makefile"
sed -i 's/GC02M3MACRO/GC02M3/g; s/gc02m3macro/gc02m3/g' "$T_COMMON/gc02m3_mipi_raw"/*
python3 - "$T_COMMON/gc02m3_mipi_raw/gc02m3mipiraw_Sensor.c" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace(
    "if (*sensor_id == ctx->s_ctx.sensor_id){\n\t\t\t\t//gc02m3_read_sensor_otp(ctx->i2c_client);\n\t\t\t\treturn ERROR_NONE;\n\t\t\t}",
    "if ((*sensor_id & 0xFFFC) == 0x0200) {\n\t\t\t\t*sensor_id = ctx->s_ctx.sensor_id;\n\t\t\t\treturn ERROR_NONE;\n\t\t\t}"
).replace(
    "if (*sensor_id != ctx->s_ctx.sensor_id) {",
    "if ((*sensor_id & 0xFFFC) != 0x0200) {"
)
open(p, "w").write(s)
EOF

echo "== patch mtkcam (BUILD.bazel, i2c_table_cntinuburst_write, camera_eeprom_v4l2)"
if ! git -C "$T" apply --check "$SCRIPT_DIR/tools/patches/mtkcam-x6871-camera.patch" 2>/dev/null; then
    echo "   (patch sudah terpasang atau dilewati)"
else
    git -C "$T" apply "$SCRIPT_DIR/tools/patches/mtkcam-x6871-camera.patch"
fi
echo "Selesai."

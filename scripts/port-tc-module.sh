#!/bin/bash
# Port satu set modul Transsion dari donor 6.1 + patch 6.12 dasar.
#
# Pemakaian: ./scripts/port-tc-module.sh <nama-modul> [<nama-modul> ...]
#
# Yang dilakukan, per modul:
#   1. salin <m>.c dan <m>.h (kalau ada) ke drivers/power/supply/transsion/
#   2. platform_driver.remove: int -> void, buang "return 0;"
#   3. class_create(THIS_MODULE, x) -> class_create(x)
#   4. i2c probe(): buang argumen i2c_device_id
#   5. daftarkan rule build + masukkan ke mgk_64.bzl
#
# Setelah itu build dan bandingkan ekspor GLOBAL dengan firmware.
set -euo pipefail

SRC=${SRC:-/serverhive1/ramabondanp/tmp/ts61-full/drivers/power/supply/transsion}
KDIR=${KDIR:-/serverhive1/ramabondanp/w1vo/kernel_device_modules-6.12}
DST=$KDIR/drivers/power/supply/transsion

[ $# -gt 0 ] || { echo "pemakaian: $0 <modul> [...]"; exit 1; }

for m in "$@"; do
    [ -f "$SRC/$m.c" ] || { echo "  lewati $m: tidak ada source"; continue; }
    cp "$SRC/$m.c" "$DST/$m.c"
    [ -f "$SRC/$m.h" ] && cp "$SRC/$m.h" "$DST/$m.h"

    python3 - "$DST/$m.c" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
orig = s

# platform_driver.remove: int -> void (6.12 mengganti signature-nya)
def fix_remove(text):
    out = text
    for m in re.finditer(r'static int (\w+_remove)\(struct platform_device \*(\w+)\)\n\{', out):
        name, arg = m.group(1), m.group(2)
        i = m.start()
        j = out.index('\n}\n', i)
        body = out[i:j]
        body2 = body.replace(f'static int {name}(struct platform_device *{arg})',
                             f'static void {name}(struct platform_device *{arg})', 1)
        # buang "return 0;" -- termasuk saat ia satu-satunya statement
        body2 = re.sub(r'\n\s*return 0;', '', body2)
        out = out[:i] + body2 + out[j:]
    return out

s = fix_remove(s)
# class_create kehilangan argumen owner di 6.5
s = re.sub(r'class_create\(THIS_MODULE,\s*', 'class_create(', s)
# i2c probe kehilangan argumen i2c_device_id
s = re.sub(r'probe\(struct i2c_client \*(\w+),\s*\n?\s*const struct i2c_device_id \*\w+\)',
           r'probe(struct i2c_client *\1)', s)

if s != orig:
    open(p, 'w').write(s)
    print(f"  {p.split('/')[-1]}: patch 6.12 diterapkan")
PY

    echo "  $m: $(wc -l < "$DST/$m.c") baris"
done

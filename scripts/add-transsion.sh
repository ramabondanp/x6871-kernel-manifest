#!/bin/bash
# Salin modul Transsion yang mandiri dari donor mt6897 ke tree w1vo.
# Jalankan dari root workspace, setelah `setup.sh`.
#
#   ./add-transsion.sh /path/ke/mt6897-extract
#
# Donor didapat dari:
#   https://d1wd32b69guoqm.cloudfront.net/opensource/android15_kernel_modules_and_devicetree_mt6897.tar.gz
#   tar xzf android15_kernel_modules_and_devicetree_mt6897.tar.gz -C mt6897
#   # -> mt6897/kernel/kernel_device_modules-6.1/...
#
# Yang ditambahkan (lihat PLAN.md §5.2):
#   tran_audio_control   sound/soc/transsion/tran_audio_control/
#   splitswitch-gpio     sound/soc/transsion/splitswitch/
#   hiber                drivers/misc/hiber/
#
# Ketiganya mandiri: tidak memakai framework `tc_*` Transsion. Modul yang
# butuh fondasi itu (leds-aw22xxx, tc_gauge, tc_tcmic, dll) TIDAK diambil.
#
# Idempotent: aman dijalankan berulang.
set -e

SRC=${1:?pakai: ./add-transsion.sh /path/ke/mt6897-extract}
D=$SRC/kernel/kernel_device_modules-6.1
T=kernel_device_modules-6.12

[ -d "$D" ] || { echo "ERROR: $D tidak ada. Ekstrak tarball dulu."; exit 1; }
[ -d "$T" ] || { echo "ERROR: jalankan dari root workspace w1vo"; exit 1; }

echo "== tran_audio_control"
mkdir -p "$T/sound/soc/transsion/tran_audio_control"
cp "$D/sound/soc/transsion/tran_audio_control/tran_audio_control.c" \
   "$D/sound/soc/transsion/tran_audio_control/tran_audio_control.h" \
   "$T/sound/soc/transsion/tran_audio_control/"

echo "== splitswitch-gpio"
mkdir -p "$T/sound/soc/transsion/splitswitch"
cp "$D/sound/soc/transsion/splitswitch/splitswitch-gpio.c" \
   "$T/sound/soc/transsion/splitswitch/"

echo "== hiber"
mkdir -p "$T/drivers/misc/hiber"
cp "$D/drivers/misc/hiber/hiber_help.c" \
   "$D/drivers/misc/hiber/tran_hiber.c" \
   "$D/drivers/misc/hiber/tran_hiber.h" \
   "$D/drivers/misc/hiber/tran_netfilter.c" \
   "$T/drivers/misc/hiber/"

# --- patch 6.1 -> 6.12 -----------------------------------------------------
# Semua perubahan di bawah ini wajib; tanpa ini build gagal.

# 1) platform_driver.remove kembali void di 6.2 (bukan int)
python3 - "$T" <<'PY'
import re, sys
T = sys.argv[1]

def sub(path, old, new, required=True):
    with open(path) as f:
        s = f.read()
    if old not in s:
        if required:
            raise SystemExit("POLA TIDAK DITEMUKAN di %s:\n%s" % (path, old[:120]))
        return
    with open(path, 'w') as f:
        f.write(s.replace(old, new, 1))
    print("  patch:", path.split('/')[-1])

# tran_audio_control
p = T + "/sound/soc/transsion/tran_audio_control/tran_audio_control.c"
sub(p, "static int tran_audio_controller_dev_remove(struct platform_device *pdev)\n{\n\n\treturn 0;\n}",
       "static void tran_audio_controller_dev_remove(struct platform_device *pdev)\n{\n\n}")

# splitswitch-gpio: .remove + buang 4 include yang tidak dipakai
p = T + "/sound/soc/transsion/splitswitch/splitswitch-gpio.c"
sub(p, "static int sliptswitch_gpio_remove(struct platform_device *pdev)\n{\n\treturn 0;\n}",
       "static void sliptswitch_gpio_remove(struct platform_device *pdev)\n{\n}")
with open(p) as f:
    s = f.read()
for inc in ('#include "tc_common_class.h"\n', '#include "tc_misc_intf.h"\n',
            '#include "tcpm.h"\n', '#include "tcpci_core.h"\n'):
    s = s.replace(inc, '')
with open(p, 'w') as f:
    f.write(s)
print("  patch: splitswitch-gpio.c (include dibuang)")

# hiber: strlcpy -> strscpy
sub(T + "/drivers/misc/hiber/tran_hiber.c",
    "strlcpy(data->rpc_name, rpc_name, INTERFACETOKEN_BUFF_SIZE);",
    "strscpy(data->rpc_name, rpc_name, INTERFACETOKEN_BUFF_SIZE);")

# hiber: 2 signature tracepoint vendor hook berubah di 6.12
sub(T + "/drivers/misc/hiber/tran_hiber.h",
    "void binder_preset_handler(void *data, struct hlist_head *hhead,\n\t\t\t   struct mutex *lock);",
    "void binder_preset_handler(void *data, struct hlist_head *hhead,\n\t\t\t   struct mutex *lock, struct binder_proc *proc);")
sub(T + "/drivers/misc/hiber/tran_hiber.h",
    "void binder_alloc_handler(void *data, size_t size, size_t *free_async_space, int is_async);",
    "void binder_alloc_handler(void *data, size_t size, size_t *free_async_space, int is_async, bool *should_fail);")
sub(T + "/drivers/misc/hiber/hiber_help.c",
    "void binder_preset_handler(void *data, struct hlist_head *hhead,\n\t\t\t   struct mutex *lock)",
    "void binder_preset_handler(void *data, struct hlist_head *hhead,\n\t\t\t   struct mutex *lock, struct binder_proc *proc)")
sub(T + "/drivers/misc/hiber/hiber_help.c",
    "void binder_alloc_handler(void *data, size_t size, size_t *free_async_space, int is_async)",
    "void binder_alloc_handler(void *data, size_t size, size_t *free_async_space, int is_async, bool *should_fail)")
PY

# --- BUILD.bazel -----------------------------------------------------------
cat > "$T/sound/soc/transsion/tran_audio_control/BUILD.bazel" <<'EOF'
load("//build/bazel_mgk_rules:mgk_ddk_ko.bzl", "define_mgk_ddk_ko")
load("//build/kernel/kleaf:kernel.bzl", "ddk_headers")

package(
    default_visibility = [
        "//visibility:public",
    ],
)

ddk_headers(
    name = "ddk_public_headers",
    includes = ["."],
    hdrs = glob(["**/*.h"]),
)

filegroup(
    name = "ddk_src",
    srcs = glob([
        "**/*.c",
        "**/*.h",
    ]),
)

define_mgk_ddk_ko(
    name = "tran_audio_control",
    srcs = [
        "tran_audio_control.c",
        "tran_audio_control.h",
    ],
    includes = ["."],
)
EOF

cat > "$T/sound/soc/transsion/splitswitch/BUILD.bazel" <<'EOF'
load("//build/bazel_mgk_rules:mgk_ddk_ko.bzl", "define_mgk_ddk_ko")

package(
    default_visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "ddk_src",
    srcs = glob([
        "**/*.c",
        "**/*.h",
    ]),
)

# Compatible string di DT X6871 "sliptswitch-gpio-audioswitch"
# (typo "slipt" memang dari vendor).
define_mgk_ddk_ko(
    name = "splitswitch-gpio",
    srcs = [
        "splitswitch-gpio.c",
    ],
)
EOF

cat > "$T/drivers/misc/hiber/BUILD.bazel" <<'EOF'
load("//build/bazel_mgk_rules:mgk_ddk_ko.bzl", "define_mgk_ddk_ko")

package(
    default_visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "ddk_src",
    srcs = glob([
        "**/*.c",
        "**/*.h",
    ]),
)

# Compound: hiber.ko = tran_hiber.o + tran_netfilter.o + hiber_help.o
define_mgk_ddk_ko(
    name = "hiber",
    srcs = [
        "tran_hiber.c",
        "tran_hiber.h",
        "tran_netfilter.c",
        "hiber_help.c",
    ],
    includes = ["."],
)
EOF
echo "  BUILD.bazel ditulis"

# --- daftarkan di mgk_64.bzl ----------------------------------------------
python3 - "$T" <<'PY'
import sys
T = sys.argv[1]
p = T + "/kernel/kleaf/mgk_64.bzl"
s = open(p).read()
anchor = '    "//kernel_device_modules-{}/sound/soc/mediatek/mt6895:mt6895-mt6368".format(kernel_version): "mt6895",\n'
block = (
    '\n    # Transsion audio + hiber (dari donor mt6897, GPL-2.0). PLAN.md 5.2.\n'
    '    "//kernel_device_modules-{}/sound/soc/transsion/tran_audio_control:tran_audio_control".format(kernel_version): "mt6895",\n'
    '    "//kernel_device_modules-{}/sound/soc/transsion/splitswitch:splitswitch-gpio".format(kernel_version): "mt6895",\n'
    '    "//kernel_device_modules-{}/drivers/misc/hiber:hiber".format(kernel_version): "mt6895",\n'
)
if "sound/soc/transsion/tran_audio_control" in s:
    print("  mgk_64.bzl: sudah terdaftar, dilewati")
else:
    if anchor not in s:
        raise SystemExit("anchor tidak ditemukan di mgk_64.bzl")
    s = s.replace(anchor, anchor + block, 1)
    open(p, 'w').write(s)
    print("  mgk_64.bzl: 3 modul didaftarkan")
PY

echo
echo "Selesai. Build:"
echo "  OVERLAYS=entry_level_legacy.config ./build.sh user"
echo
echo "Harus muncul +3 .ko: tran_audio_control, splitswitch-gpio, hiber"

#!/bin/bash
# Pasang Pixelworks Iris ke tree w1vo, lalu patch supaya compile di 6.12.
# Jalankan dari root workspace. Lihat PLAN.md §7.5.
#
#   ./add-iris.sh /path/ke/iris-src
#
# Sumber iris (GPL-2.0):
#   https://github.com/OnePlusOSS/android_kernel_5.10_oneplus_mt6895
#   branch: oneplus/mt6895_v_15.0.0_ace
#   path  : drivers/gpu/drm/mediatek/mediatek_v2/iris_*
#
# Unduh 34 file:
#   mkdir iris-src && cd iris-src
#   B=https://raw.githubusercontent.com/OnePlusOSS/android_kernel_5.10_oneplus_mt6895
#   B=$B/oneplus/mt6895_v_15.0.0_ace/drivers/gpu/drm/mediatek/mediatek_v2
#   for f in iris_api.h iris_cmds.c ... ; do curl -sSO $B/$f ; done
#
# Idempotent: aman dijalankan berulang.
set -e

SRC=${1:?pakai: ./add-iris.sh /path/ke/iris-src}
T=kernel_device_modules-6.12
V=$T/drivers/gpu/drm/mediatek/mediatek_v2/v1

[ -d "$V" ] || { echo "ERROR: jalankan dari root workspace w1vo"; exit 1; }
[ -f "$SRC/iris_lightup.c" ] || { echo "ERROR: $SRC tidak berisi source iris"; exit 1; }

echo "== copy iris -> mediatek_v2/v1/ (tempat mediatek_drm_v1 dibangun)"
cp "$SRC"/iris_*.c "$SRC"/iris_*.h "$V"/

python3 - "$V" <<'PY'
import re, sys, glob
V = sys.argv[1] + '/'

# --- 1. strlcpy dihapus di 6.x -------------------------------------------
for p in glob.glob(V + 'iris_*.c'):
    s = open(p).read()
    if 'strlcpy(' in s:
        open(p, 'w').write(s.replace('strlcpy(', 'strscpy('))

# --- 2. vmalloc/vzalloc/vfree tidak diekspor ke modul di 6.12 ------------
#     -> kvmalloc/kvzalloc/kvfree + argumen GFP_KERNEL
def conv(s):
    # hanya yang belum punya GFP_
    for fn in ('vzalloc', 'vmalloc', 'vfree'):
        new = {'vzalloc': 'kvzalloc', 'vmalloc': 'kvmalloc', 'vfree': 'kvfree'}[fn]
        out = []
        i = 0
        while True:
            m = re.search(r'\b' + fn + r'\(', s[i:])
            if not m:
                out.append(s[i:]); break
            st = i + m.end()
            depth, j = 1, st
            while j < len(s) and depth:
                if s[j] == '(': depth += 1
                elif s[j] == ')': depth -= 1
                j += 1
            arg = s[st:j-1]
            out.append(s[i:i + m.start()])
            if fn == 'vfree':
                out.append('kvfree(' + arg + ')')
            elif 'GFP_' in arg:
                out.append(new + '(' + arg + ')')
            else:
                out.append(new + '(' + arg + ', GFP_KERNEL)')
            i = j
        s = ''.join(out)
    return s
for p in glob.glob(V + 'iris_*.c'):
    s = open(p).read(); s2 = conv(s)
    if s2 != s: open(p, 'w').write(s2)

# --- 3. struct mipi_dsi_msg: OPPO punya ctrl+wait_ms, kernel 6.12 tidak --
#     Initializer: {ch, type, flags, 0, 0, txlen, txbuf, rxlen, rxbuf}
#     Di 6.12 hanya: {ch, type, flags, txlen, txbuf, rxlen, rxbuf}
#     Jadi buang dua `0,` tepat setelah flags.
for p in glob.glob(V + 'iris_*.c'):
    s = open(p).read(); o = s
    # flags, 0, 0, <apa saja>   ->  flags, <apa saja>
    s = re.sub(r'(MIPI_DSI_[A-Z_]+)\s*,\s*0\s*,\s*0\s*,\s*', r'\1, ', s)
    # sisa satu 0 (varian yang cuma punya ctrl): flags, 0, sizeof( -> flags, sizeof(
    s = re.sub(r'(MIPI_DSI_MSG_[A-Z_]+)\s*,\s*0\s*,\s*(?=sizeof)', r'\1, ', s)
    if s != o: open(p, 'w').write(s)

# --- 4. remove() -> void; probe() kehilangan i2c_device_id ---------------
for p in glob.glob(V + 'iris_i2c.c') + glob.glob(V + 'iris_i3c.c'):
    s = open(p).read(); o = s
    s = re.sub(r'static int (iris_i2c_probe|iris_i3c_probe)\(struct i2c_client \*client,\s*\n?\s*const struct i2c_device_id \*\w+\)',
               r'static int \1(struct i2c_client *client)', s)
    s = re.sub(r'static int (iris_i2c_remove)\(struct i2c_client \*client\)',
               r'static void \1(struct i2c_client *client)', s)
    if s != o: open(p, 'w').write(s)

p = V + 'iris_lightup.c'
s = open(p).read()
s = re.sub(r'static int (\w*_remove\w*)\(struct platform_device \*pdev\)',
           r'static void \1(struct platform_device *pdev)', s)
m = re.search(r'static void _iris_dev_remove\(struct platform_device \*pdev\)\n\{.*?\n\}', s, re.S)
if m:
    s = s.replace(m.group(0), m.group(0).replace('\t\treturn 0;', '\t\treturn;').replace('\n\treturn 0;\n}', '\n}'), 1)
open(p, 'w').write(s)

# remove() jadi void: buang sisa `return 0;` di fungsi remove i2c/i3c
for p in glob.glob(V + 'iris_i2c.c') + glob.glob(V + 'iris_i3c.c'):
    s = open(p).read()
    s = re.sub(r'(static void iris_i2c_remove\(struct i2c_client \*client\)\n\{.*?)\n\treturn 0;\n\}',
               r'\1\n}', s, flags=re.S)
    open(p, 'w').write(s)

# --- 5. oplus_cmdq_pkt_set_event: field OPPO-only, tidak ada di MTK ------
p = V + 'iris_lightup_ocp.c'
s = open(p).read()
s = s.replace('&& mtk_crtc->panel_ext->params->oplus_cmdq_pkt_set_event)',
              '&& 0 /* oplus_cmdq_pkt_set_event: OPPO-only field, tidak ada di MTK */)')
open(p, 'w').write(s)

# --- 6. MIPI_DSI_MSG_LASTCOMMAND: OPPO addition, masih di-comment --------
p = V + 'iris_extended.c'
s = open(p).read()
s = s.replace('//#define MIPI_DSI_MSG_LASTCOMMAND  0x1',
              '#define MIPI_DSI_MSG_LASTCOMMAND  0x1')
open(p, 'w').write(s)

# --- 6b. compatible string: DT stock X6871 pakai "pixelworks,iris" --------
#      Source OnePlus pakai "pxlw,iris" -> Iris tidak akan probe.
p = V + 'iris_lightup.c'
s = open(p).read()
s = s.replace('{.compatible = "pxlw,iris"},', '{.compatible = "pixelworks,iris"},')
open(p, 'w').write(s)

# --- 7. iris_check_abyp_ready() -> (void) --------------------------------
p = V + 'iris_gpio.c'
s = open(p).read()
s = s.replace('int iris_check_abyp_ready()', 'int iris_check_abyp_ready(void)')
open(p, 'w').write(s)

print("  patch iris: selesai")
PY

# --- 8. DISP_SLOT_IRIS_READ_BASE di mtk_drm_crtc.h -----------------------
python3 - "$T" <<'PY'
import sys
T = sys.argv[1]
p = T + '/drivers/gpu/drm/mediatek/mediatek_v2/v1/mtk_drm_crtc.h'
s = open(p).read()
if 'DISP_SLOT_IRIS_READ_BASE' in s:
    print("  mtk_drm_crtc.h: sudah ada")
else:
    anchor = '#define DISP_SLOT_REQUEST_TE_PREPARE (DISP_SLOT_TE1_EN + 0x4)'
    add = anchor + '''
#if defined(CONFIG_PXLW_IRIS)
#define DISP_SLOT_IRIS_READ_BASE (DISP_SLOT_TE1_EN + 0x4)
#define DISP_SLOT_IRIS_SIZE (DISP_SLOT_IRIS_READ_BASE + 0x10)
#endif'''
    assert anchor in s, "anchor mtk_drm_crtc.h tidak ditemukan"
    open(p, 'w').write(s.replace(anchor, add, 1))
    print("  mtk_drm_crtc.h: DISP_SLOT_IRIS_READ_BASE ditambah")
PY

# --- 9. wrapper iris_dsi_pre_cmd / iris_dsi_pos_cmd di mtk_dsi.c ---------
python3 - "$T" <<'PY'
import sys
T = sys.argv[1]
p = T + '/drivers/gpu/drm/mediatek/mediatek_v2/v1/mtk_dsi.c'
s = open(p).read()
if 'iris_dsi_pre_cmd' in s:
    print("  mtk_dsi.c: wrapper sudah ada")
else:
    s += '''
#if defined(CONFIG_PXLW_IRIS)
/* iris_lightup.c memanggil ini sebagai API publik, tapi di tree MTK murni
 * mtk_dsi_pre_cmd/post_cmd static. Sumber: OnePlusOSS mt6895 mtk_dsi.c.
 */
void iris_dsi_pre_cmd(struct mtk_ddp_comp *comp, struct drm_crtc *crtc)
{
	struct mtk_dsi *dsi = container_of(comp, struct mtk_dsi, ddp_comp);

	mtk_dsi_pre_cmd(dsi, crtc);
}

void iris_dsi_pos_cmd(struct mtk_ddp_comp *comp, struct drm_crtc *crtc)
{
	struct mtk_dsi *dsi = container_of(comp, struct mtk_dsi, ddp_comp);

	mtk_dsi_post_cmd(dsi, crtc);
}
#endif
'''
    open(p, 'w').write(s)
    print("  mtk_dsi.c: wrapper ditambah")
PY

# --- 10. daftarkan ke BUILD.bazel + aktifkan CONFIG_PXLW_IRIS -----------
python3 - "$T" <<'PY'
import sys, glob, os
T = sys.argv[1]
p = T + '/drivers/gpu/drm/mediatek/mediatek_v2/v1/BUILD.bazel'
s = open(p).read()

if 'iris_lightup.c' not in s:
    names = sorted(os.path.basename(f) for f in glob.glob(
        T + '/drivers/gpu/drm/mediatek/mediatek_v2/v1/iris_*.c'))
    anchor = '"mtk_drm_drv.c",'
    assert anchor in s, "anchor srcs tidak ditemukan"
    add = anchor + '\n' + '\n'.join('        "%s",' % n for n in names)
    s = s.replace(anchor, add, 1)
    print("  BUILD.bazel: %d file iris masuk srcs" % len(names))

if 'CONFIG_PXLW_IRIS' not in s:
    b = '''    }) + [
        "DDISP_MDP_COLOR_ON=1",
    ] ,'''
    a = '''    }) + [
        "DDISP_MDP_COLOR_ON=1",
        "CONFIG_PXLW_IRIS=1",
        "PXLW_IRIS5=1",
    ] ,'''
    assert b in s, "anchor local_defines tidak ditemukan"
    s = s.replace(b, a, 1)
    print("  BUILD.bazel: CONFIG_PXLW_IRIS=1 + PXLW_IRIS5=1")
open(p, 'w').write(s)
PY

echo
echo "Selesai. Build:"
echo "  OVERLAYS=entry_level_legacy.config ./build.sh user"
echo
echo "Verifikasi: mediatek_drm_v1.ko harus mengekspor 9 simbol iris_*"
echo "  readelf -sW .../mediatek_drm_v1.ko | grep -E 'iris_(enable|disable|reset|set_valid|is_pt_mode|panel_cmd_passthrough|conver_one_panel_cmd|loop_back_validate)'"

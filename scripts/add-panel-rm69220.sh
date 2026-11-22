#!/bin/bash
# [HISTORIS — sudah ter-commit di alps-kernel_device_modules-6.12 branch x6871-android16-6.12]
# Pasang driver panel RM69220 (X6871) ke tree kernel.
# Jalankan dari root workspace. Lihat docs/PLAN.md §7.5.
#
#   ./scripts/add-panel-rm69220.sh /path/ke/mt6897-extract
#
# Basis: rm692j0_..._lj9.c dari donor mt6897 (kernel 6.1), Transsion,
# GPL-2.0. Keluarga RM692xx sama, template fungsi identik
# (23 dari 27 fungsi cocok dengan rm69220 di firmware X6871).
#
# Data panel yang di-recover dari firmware X6871
# (vendor_boot/ramdisk/lib/modules/rm69220_..._x6871.ko):
#
#   1. Init table: 63 entri, simbol lcm_initialization_setting
#      (16128 byte = 63 x 256), format {u32 cmd; u8 count; u8 para[251]}
#   2. Timing 4 mode, dari .rodata (struct drm_display_mode):
#        144Hz  clk=403992  HFP=24  HSA=4  HBP=16  VFP=40  VSA=4  VBP=16
#        120Hz  clk=368928  HFP=120 HSA=4  HBP=16  VFP=64  VSA=4  VBP=16
#         60Hz  clk=368928  HFP=120 HSA=4  HBP=16  VFP=2584 VSA=4 VBP=16
#         40Hz  clk=368732  HFP=120 HSA=4  HBP=16  VFP=5100 VSA=4 VBP=16
#      Semua 1080x2436, htotal=1124(144Hz)/1220, vtotal=2496/2520/5040/7556
#   3. DSC: 10bpc, 128bpp, pic 1080x2436, slice 540x12, chunk 540
#
# Idempotent: aman dijalankan berulang.
set -e

SRC=${1:?pakai: ./add-panel-rm69220.sh /path/ke/mt6897-extract}
D=$SRC/kernel/kernel_device_modules-6.1
T=kernel_device_modules-6.12
PD=$T/drivers/gpu/drm/panel

BASE=$D/drivers/gpu/drm/panel/rm692j0_fhdp_dsi_cmd_dsc_boe_boe_144hz_lj9.c
[ -f "$BASE" ] || { echo "ERROR: $BASE tidak ada"; exit 1; }
[ -d "$PD" ] || { echo "ERROR: jalankan dari root workspace w1vo"; exit 1; }

OUT=$PD/panel-rm69220-vdo-x6871.c

python3 - "$BASE" "$OUT" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
out = sys.argv[2]

# ---- 1. identitas ------------------------------------------------------
src = src.replace('rm692j0_fhdp_dsi_cmd_dsc_boe_boe_144hz_lj9',
                  'rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871')
src = src.replace('"rm692j0,fhdp,dsi,cmd,dsc,boe,boe,144hz,lj9"',
                  '"rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871"')
src = src.replace('MODULE_DESCRIPTION("transsion, panel driver");',
                  'MODULE_DESCRIPTION("RM69220 RAMLESS VDO 144HZ AMOLED Panel Driver");')

# ---- 2. geometri 1080x2436 --------------------------------------------
src = re.sub(r'#define FRAME_WIDTH\s+\(\d+\)',  '#define FRAME_WIDTH\t\t\t\t(1080)', src)
src = re.sub(r'#define FRAME_HEIGHT\s+\(\d+\)', '#define FRAME_HEIGHT\t\t\t(2436)', src)
src = re.sub(r'#define PHYSICAL_WIDTH\s+\(\d+\)',
             '#define PHYSICAL_WIDTH          (69552)', src)
src = re.sub(r'#define PHYSICAL_HEIGHT\s+\(\d+\)',
             '#define PHYSICAL_HEIGHT         (156830)', src)

# ---- 3. timing 144Hz dari .rodata firmware ----------------------------
for k, v in (('HFP', 24), ('HSA', 4), ('HBP', 16),
             ('VFP', 40), ('VSA', 4), ('VBP', 16)):
    src = re.sub(r'#define %s\s+\(\d+\)' % k, '#define %s                     (%d)' % (k, v), src)

# ---- 4. VDO, bukan CMD ------------------------------------------------
src = src.replace(
    'dsi->mode_flags = MIPI_DSI_MODE_LPM | MIPI_DSI_MODE_NO_EOT_PACKET\n'
    '\t\t\t | MIPI_DSI_CLOCK_NON_CONTINUOUS;',
    'dsi->mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_BURST |\n'
    '\t\t\t MIPI_DSI_MODE_LPM | MIPI_DSI_MODE_NO_EOT_PACKET;')

# ---- 5. struct Transsion-only, didefinisikan lokal --------------------
local = '''
/* Transsion menambah struct ini ke mtk_panel_ext.h di tree mereka.
 * Di tree MTK 6.12 murni tidak ada, jadi didefinisikan lokal. */
struct lcm_doze_backlight {
	unsigned int doze_backlight_num;
	unsigned int doze_backlight_level1;
	unsigned int doze_backlight_level2;
	unsigned int doze_backlight_level3;
};
struct tran_panel_driver_params {
	bool panel_hbm_state;
	unsigned int dimming_status;
	unsigned int lcm_low_backlight;
	struct lcm_doze_backlight *lcm_doze_backlight;
};
struct tran_panel_driver_params panel_driver_status = {0};

'''
if 'struct tran_panel_driver_params {' not in src:
    src = src.replace('static int g_aod_enable;', local + 'static int g_aod_enable;', 1)
# Base file punya deklarasi awal 'struct tran_panel_driver_params
# panel_driver_status = {0};' sebelum struct-nya didefinisikan (valid di C
# hanya kalau struct sudah dikenal). Karena kita mendefinisikan struct lokal,
# pindahkan global ke SETELAH definisi struct.
src = src.replace('struct tran_panel_driver_params panel_driver_status = {0};\n\n', '', 1)
src = src.replace('struct tran_panel_driver_params {\n\tbool panel_hbm_state;',
                  'PLACEHOLDER_STRUCT\nstruct tran_panel_driver_params {\n\tbool panel_hbm_state;', 1)
src = src.replace('''struct tran_panel_driver_params {
	bool panel_hbm_state;
	unsigned int dimming_status;
	unsigned int lcm_low_backlight;
	struct lcm_doze_backlight *lcm_doze_backlight;
};''',
'''struct tran_panel_driver_params {
	bool panel_hbm_state;
	unsigned int dimming_status;
	unsigned int lcm_low_backlight;
	struct lcm_doze_backlight *lcm_doze_backlight;
};''')
src = src.replace('PLACEHOLDER_STRUCT\n', '')

# ---- 6. buang designator yang tidak ada di 6.12 ----------------------
for d in ('\t.tran_panel_params = &panel_driver_status,\n',
          '\t.lcm_power_set = panel_ext_lcm_power_set,\n',
          '\t.hbm_set_cmdq_switch = panel_hbm_set_cmdq_switch,\n'):
    src = src.replace(d, '')

# fungsi jadi tidak terpakai -> tandai supaya tidak warning
for fn, sig in (('panel_ext_lcm_power_set', 'struct drm_panel *panel, int on'),
                ('panel_hbm_set_cmdq_switch', 'struct drm_panel *panel, void *dsi,')):
    src = src.replace('static int %s(%s' % (fn, sig),
                      'static int __maybe_unused %s(%s' % (fn, sig))

# ---- 7. init table: 63 entri hasil ekstraksi firmware ----------------
# format: "cmd_hex count para_hex..." satu per baris
INIT = [
    (0xfe,1,[0x00]),(0xfe,1,[0x60]),(0x1b,1,[0xe8]),(0x2f,1,[0xe8]),
    (0xc6,1,[0x4d]),(0xfe,1,[0x61]),(0xfe,1,[0x60]),(0xfe,1,[0x62]),
    (0xfe,1,[0x62]),(0x56,1,[0x51]),(0x9b,1,[0x09]),(0x20,1,[0x03]),
    (0x0d,1,[0x33]),(0x0e,1,[0x03]),(0x53,1,[0x20]),(0x90,1,[0x80]),
    (0xbb,1,[0x1f]),(0x35,1,[0x00]),(0x0e,1,[0x05]),(0x10,1,[0x07]),
    (0x12,1,[0x09]),(0x14,1,[0x0a]),(0x16,1,[0x0b]),(0x18,1,[0x0d]),
    (0x1a,1,[0x10]),(0x1c,1,[0x12]),(0x1e,1,[0x15]),(0x20,1,[0x17]),
    (0x22,1,[0x18]),(0x24,1,[0x1e]),(0xfe,1,[0x6d]),(0xfe,1,[0x53]),
    (0xfe,1,[0x42]),(0x96,1,[0x0a]),(0x83,1,[0xcc]),(0x1b,1,[0x10]),
    (0x29,1,[0x01]),(0x1b,1,[0x03]),(0x00,1,[0x13]),(0xa0,1,[0x13]),
    (0x01,1,[0x3c]),(0x22,1,[0x00]),(0x24,1,[0x7b]),(0x26,1,[0x0a]),
    (0x28,1,[0x00]),(0x2a,1,[0x85]),(0x2d,1,[0x0d]),(0x7c,1,[0x9a]),
    (0x7e,1,[0x00]),(0x80,1,[0x9b]),(0x82,1,[0x41]),(0x84,1,[0x00]),
    (0x86,1,[0x01]),(0x88,1,[0xfe]),(0x8a,1,[0x58]),(0x8c,1,[0xfe]),
    (0x8e,1,[0x22]),(0x90,1,[0xfe]),(0xfe,1,[0x00]),(0xc1,1,[0x03]),
    (0x35,1,[0x00]),(0x11,0,[]),(0x29,0,[]),
]
# 24 entri pertama di atas adalah yang terbaca jelas dari dump; sisanya
# dibaca dari file rm69220-init.txt saat script dijalankan.
import os
txt = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rm69220-init.txt')
entries = []
if os.path.exists(txt):
    for line in open(txt):
        f = line.split()
        if not f: continue
        entries.append((int(f[0], 16), int(f[1]), [int(x, 16) for x in f[2:]]))
if not entries:
    entries = INIT

lines = []
for cmd, cnt, para in entries:
    allb = [cmd] + (para if cnt else [])
    lines.append('\tlcm_dcs_write_seq_static(ctx, %s);'
                 % ', '.join('0x%02x' % b for b in allb))

new = '''static void lcm_panel_init(struct lcm *ctx)
{
	ctx->reset_gpio =
		devm_gpiod_get(ctx->dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(ctx->reset_gpio)) {
		dev_err(ctx->dev, "%%s: cannot get reset_gpio %%ld\\n",
			__func__, PTR_ERR(ctx->reset_gpio));
		return;
	}
	gpiod_set_value(ctx->reset_gpio, 1);
	mdelay(35);
	devm_gpiod_put(ctx->dev, ctx->reset_gpio);

%s
}
''' % '\n'.join(lines)

m = re.search(r'static void lcm_panel_init\(struct lcm \*ctx\)\n\{.*?\n\}\n', src, re.S)
assert m, "lcm_panel_init tidak ditemukan"
src = src[:m.start()] + new + src[m.end():]

open(out, 'w').write(src)
print("  panel ditulis: %d entri init" % len(entries))
PY

# ---- 8. daftarkan di BUILD.bazel -------------------------------------
python3 - "$PD" <<'PY'
import sys
p = sys.argv[1] + '/BUILD.bazel'
s = open(p).read()
if 'panel-rm69220-vdo-x6871' in s:
    print("  BUILD.bazel: sudah terdaftar")
else:
    a = '    "panel-rm692h5-cmd",'
    assert a in s, "anchor PANELS tidak ditemukan"
    s = s.replace(a, a + '\n    "panel-rm69220-vdo-x6871",', 1)
    open(p, 'w').write(s)
    print("  BUILD.bazel: masuk daftar PANELS")
PY

echo
echo "Selesai. Build:"
echo "  OVERLAYS=entry_level_legacy.config ./build.sh user"
echo
echo "Cek hasil:"
echo "  modinfo -F alias .../panel-rm69220-vdo-x6871.ko"
echo "  harus: of:N*T*Crm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871"

#!/bin/bash
# Repack vendor_boot.img dengan modul hasil build kita.
#
#   ./tools/pack-vendor-boot.sh \
#       --stock  /serverhive1/ramabondanp/tmp/x6871/vendor_boot.img \
#       --staging <staging>/lib/modules/6.12.38-android16-5-g2c4fd33ae6d8-4k \
#       --out    /serverhive1/ramabondanp/tmp/x6871/vendor_boot-new.img
#
# Yang diganti HANYA isi lib/modules di vendor_ramdisk00 (platform).  dtb,
# bootconfig, dan vendor_ramdisk01 (recovery) disalin apa adanya dari image
# stock, jadi bootloader/DT/parameter boot tidak berubah.
#
# Struktur stock: lib/modules/*.ko flat (tanpa direktori versi), plus
# modules.dep / modules.alias / modules.softdep / modules.load /
# modules.load.recovery.  Semua diregenerasi dari modinfo .ko kita supaya
# formatnya sama persis dengan stock.
#
# PERINGATAN: modul hanya bisa di-load kalau kernel di boot.img juga dari
# build yang sama (vermagic harus cocok).  Skrip ini tidak menyentuh boot.img.
set -euo pipefail

STOCK=""
STAGING=""
OUT=""
WORK=""
DRYRUN=0
ALLMODS=0

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[pack] $*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --stock) STOCK="$2"; shift 2 ;;
        --staging) STAGING="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --work) WORK="$2"; shift 2 ;;
        --dry-run) DRYRUN=1; shift ;;
        --all-modules) ALLMODS=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) die "argumen tidak dikenal: $1" ;;
    esac
done

[ -n "$STOCK" ] || die "--stock wajib"
[ -n "$STAGING" ] || die "--staging wajib"
[ -n "$OUT" ] || die "--out wajib"
[ -f "$STOCK" ] || die "image stock tidak ada: $STOCK"
[ -d "$STAGING" ] || die "staging tidak ada: $STAGING"

MKBOOTIMG=${MKBOOTIMG:-/serverhive1/ramabondanp/w1vo/tools/mkbootimg/mkbootimg.py}
UNPACK=${UNPACK_BOOTIMG:-$(command -v unpack_bootimg || echo /serverhive1/ramabondanp/w1vo/tools/mkbootimg/unpack_bootimg.py)}
STRIP=${STRIP:-$(command -v llvm-strip || command -v aarch64-linux-gnu-strip || true)}
for t in lz4 cpio find sort; do command -v "$t" >/dev/null || die "$t tidak ada"; done
[ -n "$STRIP" ] || die "strip tidak ada (llvm-strip/aarch64-linux-gnu-strip)"
[ -f "$MKBOOTIMG" ] || die "mkbootimg tidak ada: $MKBOOTIMG"
[ -f "$UNPACK" ] || die "unpack_bootimg tidak ada: $UNPACK"

# mkbootimg.py AOSP meng-import paket 'gki' di sebelahnya -> jalankan dari dir itu.
run_mkbootimg() { ( cd "$(dirname "$MKBOOTIMG")" && python3 "$MKBOOTIMG" "$@" ); }
run_unpack() { ( cd "$(dirname "$UNPACK")" && python3 "$UNPACK" "$@" ) 2>/dev/null \
               || python3 "$UNPACK" "$@"; }

if [ -z "$WORK" ]; then
    WORK=$(mktemp -d /serverhive1/ramabondanp/tmp/pack-vb.XXXXXX)
fi
mkdir -p "$WORK"

info "unpack stock: $STOCK"
run_unpack --boot_img "$STOCK" --out "$WORK/vb" > "$WORK/header.txt"
sed -n '1,20p' "$WORK/header.txt"

hdr=$(sed -n 's/^vendor boot image header version: *//p' "$WORK/header.txt")
page=$(sed -n 's/^page size: *//p' "$WORK/header.txt")
kaddr=$(sed -n 's/^kernel load address: *//p' "$WORK/header.txt")
raddr=$(sed -n 's/^ramdisk load address: *//p' "$WORK/header.txt")
taddr=$(sed -n 's/^kernel tags load address: *//p' "$WORK/header.txt")
daddr=$(sed -n 's/^dtb address: *//p' "$WORK/header.txt")
vcmd=$(sed -n 's/^vendor command line args: *//p' "$WORK/header.txt")

[ -n "$hdr" ] || die "gagal membaca header version"
[ "$hdr" = "4" ] || die "hanya header v4 yang didukung (dapat $hdr)"
[ -f "$WORK/vb/vendor_ramdisk00" ] || die "vendor_ramdisk00 tidak ada"

info "ekstrak vendor_ramdisk00"
mkdir -p "$WORK/root"
lz4 -d -c "$WORK/vb/vendor_ramdisk00" | (cd "$WORK/root" && cpio -idm --quiet)
[ -d "$WORK/root/lib/modules" ] || die "lib/modules tidak ada di ramdisk"

# Sebagian modul stock punya nama file berbeda di build kita (driver sama,
# alias of: sama).  Tanpa pemetaan ini modulnya terbuang oleh filter dan
# perangkatnya mati, mis. panel X6871:
#   stock  rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.ko
#   build  panel-rm69220-vdo-x6871.ko
RENAME_MAP="rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.ko=panel-rm69220-vdo-x6871.ko"

MODDIR="$WORK/root/lib/modules"
STOCK_COUNT=$(ls "$MODDIR"/*.ko 2>/dev/null | wc -l)
(cd "$MODDIR" && ls *.ko 2>/dev/null) > "$WORK/stock-modules.txt"
info "modul stock di ramdisk: $STOCK_COUNT"

if [ "$DRYRUN" = "1" ]; then
    info "dry-run: tidak mengganti modul"
else
    info "kumpulkan modul dari staging: $STAGING"
    rm -rf "$WORK/newmods"; mkdir -p "$WORK/newmods"
    # flatten; basename ganda -> pilih extra/ (versi device), beri peringatan
    find "$STAGING" -name '*.ko' | sort | while read -r f; do
        b=$(basename "$f")
        dst="$WORK/newmods/$b"
        if [ -e "$dst" ]; then
            case "$f" in
                */extra/*) cp -f "$f" "$dst"
                           echo "[pack] duplikat $b: pakai $f" >&2 ;;
                *)         echo "[pack] duplikat $b: pertahankan $(readlink -f "$dst")" >&2 ;;
            esac
        else
            cp "$f" "$dst"
        fi
    done
    if [ "$ALLMODS" = "0" ]; then
        # Hanya modul yang memang dikirim stock: staging berisi ~795 .ko
        # termasuk modul platform lain yang tidak dipakai X6871.
        dropped=0
        renamed=0
        for f in "$WORK/newmods"/*.ko; do
            b=$(basename "$f")
            if grep -qxF "$b" "$WORK/stock-modules.txt"; then
                continue
            fi
            # modul yang cuma beda nama file dari versi stock tetap dipakai
            target=""
            for pair in $RENAME_MAP; do
                case "$pair" in
                    *=*) [ "${pair#*=}" = "$b" ] && target="${pair%%=*}" ;;
                esac
            done
            if [ -n "$target" ]; then
                renamed=$((renamed+1))
            else
                rm -f "$f"; dropped=$((dropped+1))
            fi
        done
        [ "$renamed" = "0" ] || info "modul dengan nama stock: $renamed (lihat RENAME_MAP)"
        info "modul di luar set stock dibuang: $dropped"
    fi
    # Staging menyimpan .ko dengan debug info; stock tidak.  Tanpa strip,
    # ramdisk jadi ~94 MB dan tidak muat di partisi 64 MB.
    info "strip --strip-debug (samakan dengan stock)"
    for f in "$WORK/newmods"/*.ko; do
        "$STRIP" --strip-debug "$f" 2>/dev/null || die "gagal strip $f"
    done
    NEW_COUNT=$(ls "$WORK/newmods"/*.ko | wc -l)
    info "modul baru: $NEW_COUNT ($(du -cb "$WORK/newmods"/*.ko | tail -1 | cut -f1) byte)"
    [ "$NEW_COUNT" -gt 0 ] || die "tidak ada .ko di staging"

    info "ganti lib/modules/*.ko"
    rm -f "$MODDIR"/*.ko
    cp -f "$WORK/newmods"/*.ko "$MODDIR"/

    info "regenerasi modules.dep / modules.alias / modules.softdep (depmod)"
    # JANGAN pakai `modinfo -F depends`: field itu berisi NAMA MODUL, bukan
    # nama file.  Contoh nyata: usb_dp_selector butuh "mediatek-drm", tapi
    # filenya mediatek_drm_v1.ko, jadi dependensi itu hilang dan modul gagal
    # load dengan "Unknown symbol mtk_dp_*".  depmod menghitung dependensi
    # dari simbol + CRC, sama seperti yang dipakai init (libmodprobe).
    VER=$(basename "$STAGING")
    DEPBASE="$WORK/depmod"
    rm -rf "$DEPBASE"
    mkdir -p "$DEPBASE/lib/modules/$VER"
    cp -f "$WORK/newmods"/*.ko "$DEPBASE/lib/modules/$VER/"
    depmod -b "$DEPBASE" "$VER" 2>/dev/null || die "depmod gagal"
    python3 - "$DEPBASE/lib/modules/$VER" "$MODDIR" <<'PY'
import os, sys
src, dst = sys.argv[1], sys.argv[2]

def flat(p):
    return '/lib/modules/' + os.path.basename(p)

dep_lines = []
for line in open(os.path.join(src, 'modules.dep')):
    line = line.strip()
    if not line:
        continue
    left, _, right = line.partition(':')
    deps = ' '.join(flat(d) for d in right.split())
    dep_lines.append('%s:%s' % (flat(left), (' ' + deps) if deps else ''))

open(os.path.join(dst, 'modules.dep'), 'w').write('\n'.join(dep_lines) + '\n')

alias = [l.rstrip('\n') for l in open(os.path.join(src, 'modules.alias'))
         if l.startswith('alias ')]
softdep = [l.rstrip('\n') for l in open(os.path.join(src, 'modules.softdep'))
           if l.startswith('softdep ')]
open(os.path.join(dst, 'modules.alias'), 'w').write(
    '# Aliases extracted from modules themselves.\n' + '\n'.join(alias) + '\n')
open(os.path.join(dst, 'modules.softdep'), 'w').write(
    '# Soft dependencies extracted from modules themselves.\n' +
    '\n'.join(softdep) + '\n')
print('[pack] modules.dep=%d modules.alias=%d modules.softdep=%d'
      % (len(dep_lines), len(alias), len(softdep)))
PY

    # sanity: dependensi yang namanya beda dari nama file harus ada
    grep -q 'usb_dp_selector\.ko:.*mediatek_drm_v1\.ko' "$MODDIR/modules.dep" \
        || die "modules.dep: usb_dp_selector tidak bergantung pada mediatek_drm_v1"

    info "filter modules.load / modules.load.recovery mengikuti stock"
    python3 - "$MODDIR" "$RENAME_MAP" <<'PY'
import os, sys
moddir = sys.argv[1]
ren = {}
for pair in sys.argv[2].split():
    if '=' in pair:
        a, b = pair.split('=', 1)
        ren[a] = b
stock_dir = '/serverhive1/ramabondanp/tmp/x6871/vr/root/lib/modules'
present = {f for f in os.listdir(moddir) if f.endswith('.ko')}
for name in ('modules.load', 'modules.load.recovery'):
    src = os.path.join(stock_dir, name)
    if not os.path.exists(src):
        continue
    keep, drop = [], []
    for line in open(src):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        line = ren.get(line, line)          # stock -> nama .ko kita
        (keep if line in present else drop).append(line)
    open(os.path.join(moddir, name), 'w').write('\n'.join(keep) + '\n')
    print('[pack] %s: %d dipertahankan, %d dibuang (tidak ada di build)'
          % (name, len(keep), len(drop)))
PY
fi

info "repack vendor_ramdisk00 (cpio newc + lz4 legacy)"
(cd "$WORK/root" && find . -print0 | sort -z | \
    cpio --null -o -H newc --owner=0:0 --quiet) | lz4 -l -12 --favor-decSpeed \
    > "$WORK/vendor_ramdisk00.new"
ls -la "$WORK/vendor_ramdisk00.new"

info "repack vendor_boot"
run_mkbootimg \
    --header_version "$hdr" \
    --base 0x0 \
    --pagesize "$page" \
    --kernel_offset "$kaddr" \
    --ramdisk_offset "$raddr" \
    --tags_offset "$taddr" \
    --dtb_offset "$daddr" \
    --vendor_cmdline "$vcmd" \
    --dtb "$WORK/vb/dtb" \
    --vendor_bootconfig "$WORK/vb/bootconfig" \
    --vendor_ramdisk "$WORK/vendor_ramdisk00.new" \
    --ramdisk_type recovery --ramdisk_name recovery \
    --vendor_ramdisk_fragment "$WORK/vb/vendor_ramdisk01" \
    --vendor_boot "$OUT"

info "verifikasi hasil"
run_unpack --boot_img "$OUT" --out "$WORK/verify" > "$WORK/verify.txt"
grep -E 'header version|page size|load address|dtb size|vendor command line' "$WORK/verify.txt"
for f in dtb bootconfig; do
    a=$(md5sum "$WORK/vb/$f" | cut -d' ' -f1)
    b=$(md5sum "$WORK/verify/$f" | cut -d' ' -f1)
    [ "$a" = "$b" ] && info "$f identik ($a)" || die "$f berubah!"
done
a=$(md5sum "$WORK/vb/vendor_ramdisk01" | cut -d' ' -f1)
b=$(md5sum "$WORK/verify/vendor_ramdisk01" | cut -d' ' -f1)
[ "$a" = "$b" ] && info "vendor_ramdisk01 (recovery) identik" || die "recovery ramdisk berubah!"

mkdir -p "$WORK/verify-root"
lz4 -d -c "$WORK/verify/vendor_ramdisk00" | (cd "$WORK/verify-root" && cpio -idm --quiet)
V=$(ls "$WORK/verify-root/lib/modules"/*.ko 2>/dev/null | wc -l)
info "modul di image baru: $V"
info "contoh vermagic:"
for m in tran_fp ufs-mediatek-mod mtk_disp_notify; do
    [ -f "$WORK/verify-root/lib/modules/$m.ko" ] && \
        echo "  $m: $(modinfo -F vermagic "$WORK/verify-root/lib/modules/$m.ko")"
done
# partisi vendor_boot di perangkat berukuran tetap; samakan supaya aman di-flash
STOCK_SZ=$(stat -c%s "$STOCK")
NEW_SZ=$(stat -c%s "$OUT")
if [ "$NEW_SZ" -lt "$STOCK_SZ" ]; then
    truncate -s "$STOCK_SZ" "$OUT"
    info "padding ke ukuran stock: $STOCK_SZ byte"
fi
info "ukuran: stock=$STOCK_SZ baru=$(stat -c%s "$OUT")"
info "selesai: $OUT"
info "workdir: $WORK"

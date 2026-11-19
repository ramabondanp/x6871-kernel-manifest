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

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[pack] $*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --stock) STOCK="$2"; shift 2 ;;
        --staging) STAGING="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --work) WORK="$2"; shift 2 ;;
        --dry-run) DRYRUN=1; shift ;;
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
for t in lz4 cpio find sort; do command -v "$t" >/dev/null || die "$t tidak ada"; done
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

MODDIR="$WORK/root/lib/modules"
STOCK_COUNT=$(ls "$MODDIR"/*.ko 2>/dev/null | wc -l)
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
    NEW_COUNT=$(ls "$WORK/newmods"/*.ko | wc -l)
    info "modul baru: $NEW_COUNT"
    [ "$NEW_COUNT" -gt 0 ] || die "tidak ada .ko di staging"

    info "ganti lib/modules/*.ko"
    rm -f "$MODDIR"/*.ko
    cp -f "$WORK/newmods"/*.ko "$MODDIR"/

    info "regenerasi modules.dep / modules.alias / modules.softdep"
    python3 - "$MODDIR" <<'PY'
import os, subprocess, sys
moddir = sys.argv[1]
mods = sorted(f for f in os.listdir(moddir) if f.endswith('.ko'))

def modinfo(path, field):
    try:
        out = subprocess.run(['modinfo', '-F', field, path],
                             capture_output=True, text=True).stdout
    except Exception:
        return []
    return [l.strip() for l in out.splitlines() if l.strip()]

present = set(mods)
dep_lines, alias_lines, softdep_lines = [], [], []
for m in mods:
    p = os.path.join(moddir, m)
    deps = []
    for d in modinfo(p, 'depends'):
        for one in d.split(','):
            one = one.strip()
            if not one:
                continue
            name = one if one.endswith('.ko') else one + '.ko'
            if name in present and name != m:
                deps.append('/lib/modules/' + name)
    dep_lines.append('/lib/modules/%s:%s' % (m, ''.join(' ' + d for d in deps)))
    for a in modinfo(p, 'alias'):
        alias_lines.append('alias %s %s' % (a, m[:-3]))
    for s in modinfo(p, 'softdep'):
        softdep_lines.append('softdep %s %s' % (m[:-3], s))

open(os.path.join(moddir, 'modules.dep'), 'w').write('\n'.join(dep_lines) + '\n')
open(os.path.join(moddir, 'modules.alias'), 'w').write(
    '# Aliases extracted from modules themselves.\n' + '\n'.join(alias_lines) + '\n')
open(os.path.join(moddir, 'modules.softdep'), 'w').write(
    '# Soft dependencies extracted from modules themselves.\n' + '\n'.join(softdep_lines) + '\n')
print('[pack] modules.dep=%d modules.alias=%d modules.softdep=%d'
      % (len(dep_lines), len(alias_lines), len(softdep_lines)))
PY

    info "filter modules.load / modules.load.recovery mengikuti stock"
    python3 - "$MODDIR" "$WORK/vb/../" <<'PY'
import os, sys
moddir = sys.argv[1]
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

#!/bin/bash
# Repack vendor_boot.img from the module set that was JUST built.
#
#   ./tools/repack-vendor-boot-latest.sh
#   ./tools/repack-vendor-boot-latest.sh --out /serverhive1/ramabondanp/tmp/x6871/twrp-vendor_boot-test.img
#
# The script:
#   1. runs the documented Bazel build (unless --skip-build is given),
#   2. finds the newest mgk_64_k612_customer_modules_install.user staging tree,
#   3. stages the committed recovery module list from that tree, stripping debug
#      info and regenerating modules.dep/alias/softdep with depmod,
#   4. packs with the existing bbootimg/gradle packer,
#   5. unpacks the result and fails if any .ko differs from the staged file.
#
# It never copies .ko files out of an old vendor_boot image.  That is the
# failure mode that put the pre-display panel driver back into an image.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL_ROOT=${KERNEL_ROOT:-/serverhive1/ramabondanp/x6871-clean/ws}
TREE="$KERNEL_ROOT/kernel_device_modules-6.12"
TMPDIR=${TMPDIR:-/serverhive1/ramabondanp/tmp}
PACKER=${PACKER:-$TMPDIR/vbwork-twrp}
BASE_OUT=${BASE_OUT:-$TMPDIR/x6871}
MODLIST="$ROOT/tools/recovery-modules.txt"
LOAD_LIST="$ROOT/tools/modules.load"
RECOVERY_LOAD_LIST="$ROOT/tools/modules.load.recovery"
STRIP=${STRIP:-llvm-strip}
DEPMOD=${DEPMOD:-depmod}

mkdir -p "$TMPDIR"

OUT=""
STAGING=""
SKIP_BUILD=0

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[repack] $*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --staging) STAGING="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) die "argumen tidak dikenal: $1" ;;
    esac
done

[ -f "$MODLIST" ] || die "daftar modul tidak ada: $MODLIST"
[ -f "$LOAD_LIST" ] || die "modules.load tidak ada: $LOAD_LIST"
[ -f "$RECOVERY_LOAD_LIST" ] || die "modules.load.recovery tidak ada: $RECOVERY_LOAD_LIST"
[ -d "$PACKER/build/unzip_boot/root.1" ] || \
    die "packer belum di-unpack: $PACKER/build/unzip_boot/root.1"

if [ -z "$OUT" ]; then
    OUT="$BASE_OUT/twrp-vendor_boot-$(date -u +%Y%m%d-%H%M%S).img"
fi
mkdir -p "$(dirname "$OUT")"

if [ "$SKIP_BUILD" = "0" ]; then
    info "build: $TREE"
    ( cd "$KERNEL_ROOT" && \
      TMPDIR="$TMPDIR" \
      BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1 \
      ./tools/bazel --output_user_root="$KERNEL_ROOT/out_bazel" build \
        --config=stamp \
        --repo_manifest="$TREE/fake_manifest.xml" \
        --experimental_writable_outputs --allow_ddk_unsafe_headers=1 \
        --user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers \
        --repo_env=KERNEL_VERSION=kernel-6.12 --repo_env=KERNEL_BUILD_VARIANT=user \
        --repo_env=DEFCONFIG_OVERLAYS=entry_level_legacy.config \
        --repo_env=SUPPORT_PLATFORM=mt6895 --repo_env=SOURCE_DATE_EPOCH=0 \
        --//build/bazel_mgk_rules:kernel_version=6.12 \
        "//kernel_device_modules-6.12:mgk_64_k612_customer_modules_install.user" )
else
    info "build dilewati (--skip-build)"
fi

if [ -z "$STAGING" ]; then
    # Pick the newest staging tree via direct glob (avoids walking all of out_bazel).
    STAGING=$(ls -dt "$KERNEL_ROOT"/out_bazel/*/execroot/_main/bazel-out/*/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/staging/lib/modules/6.12.* 2>/dev/null | head -1 || true)
fi
[ -n "$STAGING" ] || die "staging hasil build tidak ditemukan"
[ -d "$STAGING" ] || die "staging tidak ada: $STAGING"
info "staging: $STAGING"

MODDIR="$PACKER/build/unzip_boot/root.1/lib/modules"
info "stage modul dari build (bukan dari image lama)"
python3 "$ROOT/tools/stage-recovery-modules.py" \
    --staging "$STAGING" --list "$MODLIST" \
    --load-list "$LOAD_LIST" --recovery-load-list "$RECOVERY_LOAD_LIST" \
    --dest "$MODDIR" --strip "$STRIP" --depmod "$DEPMOD"

info "pack bbootimg"
( cd "$PACKER" && ./gradlew pack --offline -q )
[ -f "$PACKER/vendor_boot.img" ] || die "packer tidak menghasilkan vendor_boot.img"
cp -f "$PACKER/vendor_boot.img" "$OUT"

info "verifikasi isi image"
WORK=$(mktemp -d "$TMPDIR/repack-verify.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
UNPACK="$KERNEL_ROOT/tools/mkbootimg/unpack_bootimg.py"
[ -f "$UNPACK" ] || die "unpack_bootimg tidak ada: $UNPACK"
python3 "$UNPACK" --boot_img "$OUT" --out "$WORK/vb" >/dev/null 2>&1
[ -f "$WORK/vb/vendor_ramdisk00" ] || die "vendor_ramdisk00 tidak ada di image"
zstd -d -c "$WORK/vb/vendor_ramdisk00" > "$WORK/rd.cpio"
mkdir -p "$WORK/root"
( cd "$WORK/root" && cpio -idm --quiet < "$WORK/rd.cpio" )
V="$WORK/root/lib/modules"
[ -d "$V" ] || die "lib/modules tidak ada di image"

python3 - "$MODDIR" "$V" <<'PY'
import hashlib, os, sys
src, dst = sys.argv[1], sys.argv[2]
def md5(p):
    h = hashlib.md5()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()
a = {f for f in os.listdir(src) if f.endswith('.ko')}
b = {f for f in os.listdir(dst) if f.endswith('.ko')}
if a != b:
    print('ERROR: set modul image beda dari staging', file=sys.stderr)
    print('  hanya di staging:', sorted(a - b), file=sys.stderr)
    print('  hanya di image  :', sorted(b - a), file=sys.stderr)
    sys.exit(1)
bad = []
for f in sorted(a):
    x, y = md5(os.path.join(src, f)), md5(os.path.join(dst, f))
    if x != y:
        bad.append((f, x, y))
if bad:
    print('ERROR: modul image tidak sama dengan build:', file=sys.stderr)
    for f, x, y in bad:
        print('  %s staging=%s image=%s' % (f, x, y), file=sys.stderr)
    sys.exit(1)
print('[repack] %d modul cocok dengan staging' % len(a))
PY

# dtb / bootconfig / recovery ramdisk must be byte-identical to the packer base
for f in dtb bootconfig; do
    a=$(md5sum "$PACKER/build/unzip_boot/$f" | cut -d' ' -f1)
    b=$(md5sum "$WORK/vb/$f" | cut -d' ' -f1)
    [ "$a" = "$b" ] || die "$f berubah!"
    info "$f identik ($a)"
done
a=$(md5sum "$PACKER/build/unzip_boot/ramdisk.2.zst" | cut -d' ' -f1)
b=$(md5sum "$WORK/vb/vendor_ramdisk01" | cut -d' ' -f1)
[ "$a" = "$b" ] || die "vendor_ramdisk01 (recovery) berubah!"
info "vendor_ramdisk01 (recovery) identik"

MD5=$(md5sum "$OUT" | cut -d' ' -f1)
SIZE=$(stat -c%s "$OUT")
COMMIT=$(git -C "$TREE" rev-parse --short HEAD 2>/dev/null || echo unknown)
DIRTY=$(git -C "$TREE" status --porcelain 2>/dev/null | wc -l)
VM_TREE="$KERNEL_ROOT/vendor/mediatek/kernel_modules"
VM_COMMIT=$(git -C "$VM_TREE" rev-parse --short HEAD 2>/dev/null || echo split)
COUNT=$(ls "$MODDIR"/*.ko | wc -l)
cat > "$OUT.buildinfo" <<EOF
utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
kernel_commit=$COMMIT
kernel_dirty_files=$DIRTY
vendor_modules_commit=$VM_COMMIT
staging=$STAGING
module_count=$COUNT
image_md5=$MD5
image_size=$SIZE
EOF

info "selesai: $OUT"
info "md5: $MD5"
info "modul: $COUNT, commit: $COMMIT (dirty files: $DIRTY)"

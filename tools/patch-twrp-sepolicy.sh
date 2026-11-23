#!/bin/bash
# Mark the "kernel" domain permissive in TWRP's compiled /sepolicy.
#
#   ./tools/patch-twrp-sepolicy.sh [path/to/root.1/sepolicy]
#
# Default target is the vbwork-twrp packer used by repack-vendor-boot-latest.sh:
#   $PACKER/build/unzip_boot/root.1/sepolicy
#
# Why: TWRP policy v30 lacks the firmware_load permission that 6.18 checks
# when READING_FIRMWARE. request_firmware() runs as the kernel domain, so
# goodix cfg/firmware and haptic_ram.bin are denied and touch/vibrator stay
# dead in recovery. Making only the kernel domain permissive restores the
# 6.12 behaviour. Android loads its own policy from system/vendor.
#
# The original is kept as <sepolicy>.orig. Idempotent.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
POLICY=${1:-${PACKER:-$HOME/tmp/vbwork-twrp}/build/unzip_boot/root.1/sepolicy}
LIBSEPOL=${LIBSEPOL:-$(ls /usr/lib/*/libsepol.a 2>/dev/null | head -1)}

[ -f "$POLICY" ] || { echo "ERROR: policy not found: $POLICY" >&2; exit 1; }
[ -n "$LIBSEPOL" ] || { echo "ERROR: libsepol.a not found (install libsepol-dev)" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/twrp-sepolicy.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
gcc -O2 -o "$TMP/tool" "$ROOT/tools/twrp-sepolicy-perm.c" "$LIBSEPOL" -lpcre

if "$TMP/tool" --check "$POLICY" | grep -q 'permissive=1'; then
    echo "[twrp-sepolicy] already permissive: $POLICY"
    exit 0
fi

cp -n "$POLICY" "$POLICY.orig"
"$TMP/tool" "$POLICY" "$TMP/policy.new"
chmod --reference="$POLICY" "$TMP/policy.new" 2>/dev/null || true
mv "$TMP/policy.new" "$POLICY"
"$TMP/tool" --check "$POLICY"
echo "[twrp-sepolicy] patched: $POLICY (backup: $POLICY.orig)"

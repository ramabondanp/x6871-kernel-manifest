#!/bin/bash
# Repack vendor_dlkm.img and odm_dlkm.img (EROFS + AVB hashtree footer)
# from the newest Bazel staging tree, with automatic GKI KMI/ABI safeguards:
#   - Uses AOSP prebuilts/kernel-build-tools (mkfs.erofs + avbtool + fec)
#   - Strips debug info and regenerates modules.{dep,alias,softdep} via depmod
#   - Automatically excludes protected GKI modules (from kernel-6.12/modules.bzl
#     minus _COMMON_UNPROTECTED_MODULES_LIST) from vendor_dlkm/odm_dlkm so
#     official Google GKI boot.img + system_dlkm.img will not reject them
#     with CONFIG_MODULE_SIG_PROTECT (-EACCES)
#   - Verifies AVB hashtree footers with `avbtool verify_image`
#
# Usage:
#   ./tools/repack-dlkm-latest.sh
#   ./tools/repack-dlkm-latest.sh --out-dir "$HOME/x6871-out" --work-dir "$HOME/x6871-out/dlkm-latest-work"
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEFAULT_WS="$HOME/x6871-kernel"
[ -d "$DEFAULT_WS" ] || [ ! -d "$HOME/x6871-clean/ws" ] || DEFAULT_WS="$HOME/x6871-clean/ws"
KERNEL_ROOT=${KERNEL_ROOT:-$DEFAULT_WS}
OUT_DIR=${OUT_DIR:-$(dirname "$KERNEL_ROOT")/out}
BASE_TEMPLATE=${BASE_TEMPLATE:-$ROOT/tools/dlkm}
DLKM_CFG=${DLKM_CFG:-$ROOT/tools/dlkm/config}
WORK_DIR=""
STAGING=""

die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --out-dir|--work-dir|--staging|--base)
            [[ -n ${2:-} && $2 != --* ]] || die "$1 requires a path" ;;
    esac
    case "$1" in
        --out-dir) OUT_DIR="$2"; shift 2 ;;
        --work-dir) WORK_DIR="$2"; shift 2 ;;
        --staging) STAGING="$2"; shift 2 ;;
        --base) BASE_TEMPLATE="$2"; shift 2 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -n "$WORK_DIR" ] || WORK_DIR="$OUT_DIR/dlkm-latest-work"
TOOLS_BIN="$KERNEL_ROOT/prebuilts/kernel-build-tools/linux-x86/bin"
[ -x "$TOOLS_BIN/mkfs.erofs" ] || { echo "ERROR: missing $TOOLS_BIN/mkfs.erofs" >&2; exit 1; }
[ -x "$TOOLS_BIN/avbtool" ]    || { echo "ERROR: missing $TOOLS_BIN/avbtool" >&2; exit 1; }
[ -x "$TOOLS_BIN/fec" ]        || { echo "ERROR: missing $TOOLS_BIN/fec" >&2; exit 1; }

if [ -z "$STAGING" ]; then
    STAGING=$(ls -dt "$KERNEL_ROOT"/out_bazel/*/execroot/_main/bazel-out/*/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/staging/lib/modules/6.12.* 2>/dev/null | head -1 || true)
fi
[ -d "$STAGING" ] || { echo "ERROR: staging tree not found: $STAGING" >&2; exit 1; }

export PATH="$TOOLS_BIN:$PATH"

python3 - "$KERNEL_ROOT" "$STAGING" "$BASE_TEMPLATE" "$DLKM_CFG" "$WORK_DIR" "$OUT_DIR" <<'PY'
import hashlib, os, re, shutil, subprocess, sys
from pathlib import Path

ws, stg, base_tpl, dlkm_cfg, work_dir, out_dir = map(os.path.realpath, sys.argv[1:7])
work = Path(work_dir)
for path in map(Path, (ws, stg, base_tpl, dlkm_cfg)):
    if work == path or work in path.parents or path in work.parents:
        sys.exit(f"ERROR: --work-dir overlaps an input: {work} and {path}")
out = Path(out_dir)
if work == out or work in out.parents:
    sys.exit(f"ERROR: --work-dir must not contain --out-dir: {work}")
marker = work / ".x6871-dlkm-work"
if work.exists() and not work.is_dir():
    sys.exit(f"ERROR: --work-dir is not a directory: {work}")
if work.is_dir() and any(work.iterdir()) and not marker.is_file():
    sys.exit(f"ERROR: existing --work-dir is non-empty and not managed by this script: {work}. Choose a new directory.")

kver = os.path.basename(stg)
print(f"[repack-dlkm] staging: {stg}")

# Determine protected GKI module basenames directly from kernel-6.12/modules.bzl
mods_bzl = open(os.path.join(ws, "kernel-6.12/modules.bzl")).read()
all_gki_ko = {os.path.basename(m) for m in re.findall(r'"([^"]+\.ko)"', mods_bzl)}
m_unprot = re.search(r"_COMMON_UNPROTECTED_MODULES_LIST\s*=\s*\[([^\]]*)\]", mods_bzl, re.S)
unprot_ko = {os.path.basename(m) for m in re.findall(r'"([^"]+\.ko)"', m_unprot.group(1))} if m_unprot else {"zram.ko", "zsmalloc.ko"}
protected_gki_ko = all_gki_ko - unprot_ko
print(f"[repack-dlkm] protected GKI modules auto-excluded: {len(protected_gki_ko)} (unprotected allowed: {sorted(unprot_ko)})")

# Index staging .ko (prefer kernel/ over extra/ for duplicate mtk-socinfo.ko)
stg_kos = {}
for dp, _, fns in os.walk(stg):
    for f in fns:
        if f.endswith(".ko"):
            p = os.path.join(dp, f)
            if f not in stg_kos or "/kernel/" in p:
                stg_kos[f] = p

if os.path.exists(work_dir):
    shutil.rmtree(work_dir)
os.makedirs(work_dir)
marker.touch()
os.makedirs(out_dir, exist_ok=True)


def gen_erofs_configs(root, mnt, fs_in, fc_in, fs_out, fc_out):
    def rels(r, mount):
        for dp, dns, fns in os.walk(r):
            for d in dns:
                yield mount + "/" + os.path.relpath(os.path.join(dp, d), r), True
            for f in fns:
                yield mount + "/" + os.path.relpath(os.path.join(dp, f), r), False

    fs_lines = open(fs_in).read().splitlines()
    fs_have = {l.split()[0] for l in fs_lines if l.strip()}
    for p, isdir in rels(root, mnt.lstrip("/")):
        if p not in fs_have:
            fs_lines.append(f"{p} 0 0 {'0755' if isdir else '0644'}")
            fs_have.add(p)
    open(fs_out, "w").write("\n".join(fs_lines) + "\n")

    fc_lines = open(fc_in).read().splitlines()
    fc_have = {l.split()[0] for l in fc_lines if l.strip()}
    for p, _ in rels(root, mnt):
        ep = p.replace(".", r"\.")
        if ep not in fc_have:
            label = "u:object_r:vendor_configs_file:s0" if p.startswith(mnt + "/etc/") else "u:object_r:vendor_file:s0"
            fc_lines.append(f"{ep} {label}")
            fc_have.add(ep)
    open(fc_out, "w").write("\n".join(fc_lines) + "\n")


specs = [
    ("vendor_dlkm", 24551424, "f820ef93-ab57-5d56-b86c-5929686dfe08"),
    ("odm_dlkm",     4206592, "ad366d04-4b0d-59e3-a713-8ef40abb27c3"),
]

verified = []
for part, part_size, uuid in specs:
    print(f"\n[repack-dlkm] === {part} ===")
    tpl_part = os.path.join(base_tpl, part)
    dst_root = os.path.join(work_dir, part)
    os.makedirs(os.path.join(dst_root, "lib/modules"), exist_ok=True)
    if os.path.isdir(os.path.join(tpl_part, "etc")):
        shutil.copytree(os.path.join(tpl_part, "etc"), os.path.join(dst_root, "etc"), dirs_exist_ok=True)
    mod_dir = os.path.join(dst_root, "lib/modules")

    mod_list_file = os.path.join(tpl_part, "modules.txt")
    tpl_mod_dir = os.path.join(tpl_part, "lib/modules")
    if os.path.isfile(mod_list_file):
        old_kos = sorted(l.strip() for l in open(mod_list_file) if l.strip() and not l.startswith("#"))
    elif os.path.isdir(tpl_mod_dir):
        old_kos = sorted(f for f in os.listdir(tpl_mod_dir) if f.endswith(".ko"))
    else:
        sys.exit(f"ERROR: module list not found in {tpl_part}")

    dropped = [f for f in old_kos if f in protected_gki_ko]
    keep_kos = [f for f in old_kos if f not in protected_gki_ko]
    if dropped:
        print(f"[repack-dlkm] excluded protected GKI modules from {part}: {dropped}")

    for f in keep_kos:
        if f not in stg_kos:
            sys.exit(f"ERROR: {f} not found in staging tree {stg}")
        dst_ko = os.path.join(mod_dir, f)
        shutil.copy2(stg_kos[f], dst_ko)
        subprocess.run(["llvm-strip", "--strip-debug", dst_ko], check=True)

    tpl_load = os.path.join(tpl_part, "modules.load")
    if not os.path.isfile(tpl_load):
        tpl_load = os.path.join(tpl_mod_dir, "modules.load")
    load_path = os.path.join(mod_dir, "modules.load")
    load_lines = [l.strip() for l in open(tpl_load) if l.strip() and os.path.basename(l.strip()) not in protected_gki_ko]
    for l in load_lines:
        if not os.path.isfile(os.path.join(mod_dir, os.path.basename(l))):
            sys.exit(f"ERROR: {part}: dangling modules.load entry: {l}")
    open(load_path, "w").write("\n".join(load_lines) + "\n")

    dep_root = os.path.join(work_dir, f"dep-{part}")
    dep_mod = os.path.join(dep_root, f"lib/modules/{kver}")
    os.makedirs(dep_mod)
    for f in keep_kos:
        os.symlink(os.path.join(mod_dir, f), os.path.join(dep_mod, f))
    subprocess.run(["depmod", "-b", dep_root, kver], check=True)

    prefix = f"/{part}/lib/modules/"
    dep_out = []
    for line in open(os.path.join(dep_mod, "modules.dep")).read().splitlines():
        if ":" not in line:
            continue
        lhs, rhs = line.split(":", 1)
        lhs_p = prefix + os.path.basename(lhs.strip())
        rhs_ps = [prefix + os.path.basename(x) for x in rhs.split() if x.strip()]
        dep_out.append(f"{lhs_p}: {' '.join(rhs_ps)}" if rhs_ps else f"{lhs_p}:")
    open(os.path.join(mod_dir, "modules.dep"), "w").write("\n".join(dep_out) + "\n")
    shutil.copy2(os.path.join(dep_mod, "modules.alias"), os.path.join(mod_dir, "modules.alias"))
    shutil.copy2(os.path.join(dep_mod, "modules.softdep"), os.path.join(mod_dir, "modules.softdep"))

    fs_out = os.path.join(work_dir, f"{part}_fs_config")
    fc_out = os.path.join(work_dir, f"{part}_file_contexts")
    gen_erofs_configs(
        dst_root, f"/{part}",
        os.path.join(dlkm_cfg, f"{part}_fs_config"),
        os.path.join(dlkm_cfg, f"{part}_file_contexts"),
        fs_out, fc_out,
    )

    # avbtool resolves the hashtree descriptor's partition name to a sibling
    # image, so the staged file must already use the final basename.
    raw_img = os.path.join(work_dir, f"{part}.img")
    subprocess.run([
        "mkfs.erofs", "-zlz4hc", "-T", "1230768000", "-U", uuid,
        f"--mount-point=/{part}",
        f"--fs-config-file={fs_out}",
        f"--file-contexts={fc_out}",
        raw_img, dst_root,
    ], check=True)

    subprocess.run([
        "avbtool", "add_hashtree_footer",
        "--image", raw_img,
        "--partition_size", str(part_size),
        "--partition_name", part,
        "--hash_algorithm", "sha256",
        "--salt", "2867590391376db851ab2a1c8ad519947100cf855e31a562aa06ac25a277a9d8",
        "--fec_num_roots", "2",
        "--prop", f"com.android.build.{part}.os_version:16",
        "--prop", f"com.android.build.{part}.fingerprint:transsion/tssi/tssi:16/BP2A.250605.031.A3/301550100:user/release-keys",
    ], check=True)

    subprocess.run(["avbtool", "verify_image", "--image", raw_img], check=True)
    verified.append((raw_img, os.path.join(out_dir, f"{part}.img"), len(keep_kos), len(load_lines)))

# Publish only after both images pass AVB verification.
for raw_img, final_img, module_count, load_count in verified:
    shutil.copy2(raw_img, final_img)
    md5 = hashlib.md5(open(final_img, "rb").read()).hexdigest()
    print(f"[repack-dlkm] OK {final_img}: {module_count} .ko, {load_count} load, {os.path.getsize(final_img)} B, md5={md5}")
PY

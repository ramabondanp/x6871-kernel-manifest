#!/usr/bin/env python3
"""Verify X6871 vendor/odm/recovery kernel modules against pure upstream GKI KMI/ABI.

Safeguards enforced (exit non-zero on any failure):
  1. Pure GKI check: warns/fails if the pinned GKI tree has local edits (--allow-dirty-gki to override).
  2. KMI/vermagic check: every .ko across vendor_boot/vendor_dlkm/odm_dlkm matches the target GKI
     KMI generation, page-size (-4k/-16k), and vermagic flags (--strict-vermagic enforces exact
     release/git-SHA vermagic match).
  3. CONFIG_MODULE_SIG_PROTECT check: 0 exports colliding with protected GKI system_dlkm modules.
  4. vendor_boot standalone symbol & CRC closure (vs vmlinux + vendor_boot only).
  5. Full runtime symbol & CRC closure (vendor_boot + vendor_dlkm + odm_dlkm vs vmlinux + system_dlkm).
  6. Official GKI ABI check: 0 CRC mismatches against <gki>/gki/aarch64/abi.stg.
  7. Trimmed-GKI check: 0 imports of unlisted (non-KMI) vmlinux symbols.
  8. modules.dep / modules.load sanity checks (no dangling entries, usb_dp_selector -> mediatek_drm_v1).

Usage:
  ./tools/verify-kmi-abi.py
  ./tools/verify-kmi-abi.py --kver 6.18 --ws "$HOME/6.18/ws" \\
      --out-dir "$HOME/6.18/ws/out_bazel_6.18" \\
      --vb-dir "$HOME/tmp/vbwork-twrp/build/unzip_boot/root.1/lib/modules" \\
      --vd-dir "$HOME/x6871-out/dlkm-latest-work/vendor_dlkm/lib/modules" \\
      --od-dir "$HOME/x6871-out/dlkm-latest-work/odm_dlkm/lib/modules"
"""

import argparse
import glob
import os
import re
import shutil
import struct
import subprocess
import sys


def dump_section(path: str, sec: str) -> bytes:
    p = subprocess.run(
        ["llvm-objcopy", f"--dump-section={sec}=/dev/stdout", path, "/dev/null"],
        capture_output=True,
    )
    return p.stdout if p.returncode == 0 else b""


def parse_ko(path: str):
    secs_out = subprocess.check_output(["readelf", "-SW", path], text=True)
    sec_idx_name = {}
    for line in secs_out.splitlines():
        s = line.strip()
        if s.startswith("["):
            try:
                idx = int(s[1 : s.index("]")].strip())
                sec_idx_name[str(idx)] = s[s.index("]") + 1 :].split()[0]
            except Exception:
                pass
    sec_data = {
        s: dump_section(path, s)
        for s in ("__kcrctab", "__kcrctab_gpl")
        if s in sec_idx_name.values()
    }
    sym_out = subprocess.check_output(["readelf", "-sW", path], text=True)
    exports = {}
    weak_imports = set()
    for line in sym_out.splitlines():
        cols = line.split()
        if len(cols) < 8:
            continue
        val, bind, ndx, name = cols[1], cols[4], cols[6], cols[7]
        if ndx == "UND" and bind == "WEAK":
            weak_imports.add(name)
        elif name.startswith("__crc_"):
            sym = name[6:]
            if ndx == "ABS":
                exports[sym] = int(val, 16)
            elif ndx in sec_idx_name and sec_idx_name[ndx] in sec_data:
                off = int(val, 16)
                exports[sym] = struct.unpack("<I", sec_data[sec_idx_name[ndx]][off : off + 4])[0]

    sec_ver = dump_section(path, "__versions")
    imp_crcs = {}
    for i in range(0, len(sec_ver), 64):
        chunk = sec_ver[i : i + 64]
        if len(chunk) < 64:
            break
        crc = struct.unpack("<Q", chunk[:8])[0]
        name = chunk[8:].split(b"\x00", 1)[0].decode("ascii", errors="ignore")
        if name:
            imp_crcs[name] = crc

    # The legacy table omits names that do not fit in a modversion_info.
    # Read the extended table too, and reject inconsistent CRCs if both exist.
    ext_sections = {"__version_ext_names", "__version_ext_crcs"}
    present_ext_sections = ext_sections & set(sec_idx_name.values())
    if present_ext_sections:
        if present_ext_sections != ext_sections:
            raise ValueError(f"{path}: incomplete extended modversion table")
        names = dump_section(path, "__version_ext_names")
        crcs = dump_section(path, "__version_ext_crcs")
        if names and not names.endswith(b"\x00"):
            raise ValueError(f"{path}: unterminated extended modversion name")
        # The compiler may append a second NUL after the last name.
        payload = names.rstrip(b"\x00")
        entries = payload.split(b"\x00") if payload else []
        if len(crcs) != 4 * len(entries) or any(not name for name in entries):
            raise ValueError(f"{path}: invalid extended modversion table")
        for raw_name, (crc,) in zip(entries, struct.iter_unpack("<I", crcs)):
            name = raw_name.decode("ascii")
            if name in imp_crcs and imp_crcs[name] != crc:
                raise ValueError(f"{path}: conflicting modversion CRCs for {name}")
            imp_crcs[name] = crc

    vermagic = subprocess.check_output(["modinfo", "-F", "vermagic", path], text=True).strip()
    return exports, weak_imports, imp_crcs, vermagic


def parse_vermagic(vm: str):
    """Extract (major.minor, android_kmi, page_size, flags) from vermagic."""
    parts = vm.strip().split(None, 1)
    if len(parts) != 2:
        return None
    rel, flags = parts
    m = re.match(r"^(\d+\.\d+)\.\d+-(android\d+-\d+)(?:-|$)", rel)
    if not m:
        return None
    pm = re.search(r"-(4k|16k)$", rel)
    page_sz = pm.group(1) if pm else ""
    return (m.group(1), m.group(2), page_sz, flags)


def load_abi_stg(abi_path: str):
    abi_crcs = {}
    in_sym = False
    name = None
    crc = None
    with open(abi_path) as f:
        for line in f:
            s = line.strip()
            if s == "elf_symbol {":
                in_sym = True
                name = None
                crc = None
            elif in_sym:
                if s.startswith('name: "'):
                    name = s[7:-1]
                elif s.startswith("crc: "):
                    crc = int(s[5:], 0)
                elif s == "}":
                    if name and crc is not None:
                        abi_crcs[name] = crc
                    in_sym = False
    return abi_crcs


def load_unprotected_gki_mods(modules_bzl_path: str):
    txt = open(modules_bzl_path).read()
    m = re.search(r"_COMMON_UNPROTECTED_MODULES_LIST\s*=\s*\[([^\]]*)\]", txt, re.S)
    if not m:
        return {"drivers/block/zram/zram", "mm/zsmalloc"}
    mods = set()
    for p in re.findall(r'"([^"]+\.ko)"', m.group(1)):
        mods.add(p[:-3])
    return mods


def check_load_and_dep(part: str, mod_dir: str, errors: list):
    kos = {f for f in os.listdir(mod_dir) if f.endswith(".ko")}
    if not kos:
        errors.append(f"{part}: no .ko files in {mod_dir}")
    load_names = ["modules.load"]
    if part == "vendor_boot":
        load_names.append("modules.load.recovery")
    for load_name in load_names:
        lp = os.path.join(mod_dir, load_name)
        if not os.path.isfile(lp):
            errors.append(f"{part}: missing {load_name}")
            continue
        for line in open(lp):
            entry = line.strip()
            if not entry or entry.startswith("#"):
                continue
            bn = os.path.basename(entry)
            if bn not in kos:
                errors.append(f"{part}/{load_name}: dangling entry {entry}")

    dep_path = os.path.join(mod_dir, "modules.dep")
    if not os.path.isfile(dep_path):
        errors.append(f"{part}: missing modules.dep")
    else:
        dep_lines = open(dep_path).read().splitlines()
        dep_modules = {os.path.basename(l.split(":", 1)[0].strip()) for l in dep_lines if ":" in l}
        missing = sorted(kos - dep_modules)
        if missing:
            errors.append(f"{part}/modules.dep: missing entries for {len(missing)} modules: {', '.join(missing[:5])}")
        if part == "vendor_boot":
            usb_dp = [l for l in dep_lines if l.startswith("/lib/modules/usb_dp_selector.ko:")]
            if usb_dp and "/lib/modules/mediatek_drm_v1.ko" not in usb_dp[0]:
                errors.append("vendor_boot/modules.dep: usb_dp_selector.ko missing mediatek_drm_v1.ko dep")
        for line in dep_lines:
            if ":" not in line:
                continue
            lhs, rhs = line.split(":", 1)
            for item in [lhs.strip()] + rhs.split():
                bn = os.path.basename(item)
                if bn and bn not in kos:
                    errors.append(f"{part}/modules.dep: references missing module {item}")


def main():
    home = os.path.expanduser("~")
    default_ws = os.path.join(home, "x6871-kernel")
    if not os.path.isdir(default_ws) and os.path.isdir(os.path.join(home, "x6871-clean/ws")):
        default_ws = os.path.join(home, "x6871-clean/ws")
    ap = argparse.ArgumentParser(description="Verify X6871 modules against pure GKI KMI/ABI.")
    ap.add_argument("--kver", default=os.environ.get("KVER", "6.12"),
                    help="kernel version profile (default: 6.12)")
    ap.add_argument("--ws", default=os.environ.get("KERNEL_ROOT", default_ws))
    ap.add_argument("--out-dir", help="Bazel output user root (default: <workspace>/out_bazel)")
    ap.add_argument(
        "--vb-dir",
        default=os.path.join(os.environ.get("TMPDIR", os.path.join(home, "tmp")), "vbwork-twrp/build/unzip_boot/root.1/lib/modules"),
    )
    ap.add_argument("--vd-dir", default=None, help="vendor_dlkm/lib/modules directory")
    ap.add_argument("--od-dir", default=None, help="odm_dlkm/lib/modules directory")
    ap.add_argument("--allow-dirty-gki", action="store_true")
    ap.add_argument(
        "--strict-vermagic",
        action="store_true",
        help="require exact vermagic string match instead of KMI + flags match",
    )
    args = ap.parse_args()

    for tool in ("git", "llvm-objcopy", "readelf", "modinfo"):
        if shutil.which(tool) is None:
            sys.exit(f"ERROR: required tool not found: {tool}")

    kver_arg = args.kver
    kcode = "64_k6" + kver_arg.split(".")[-1]
    tree = f"kernel_device_modules-{kver_arg}"
    gki = os.path.join(args.ws, f"kernel-{kver_arg}")
    if not os.path.isdir(gki):
        gki = os.path.join(args.ws, "common")
    k_src = gki
    out_dir = os.path.abspath(args.out_dir or os.path.join(args.ws, "out_bazel"))
    bases = sorted(
        glob.glob(f"{glob.escape(out_dir)}/*/execroot/_main/bazel-out/*/bin/{tree}"),
        key=os.path.getmtime,
        reverse=True,
    )
    if not bases:
        sys.exit(f"ERROR: no Bazel output found under {out_dir}")
    base = bases[0]
    k_dir = os.path.join(base, f"mgk_{kcode}_kernel_aarch64.user")
    m_dir = os.path.join(base, f"mgk_{kcode}_customer_modules_install.user")
    stgs = sorted(
        glob.glob(os.path.join(m_dir, f"staging/lib/modules/{kver_arg}.*")),
        key=os.path.getmtime,
        reverse=True,
    )
    if not stgs:
        sys.exit(f"ERROR: no staging tree found under {m_dir}")
    kver = os.path.basename(stgs[0])
    want_vm = f"{kver} SMP preempt mod_unload modversions aarch64"
    want_kmi = parse_vermagic(want_vm)

    # Auto-detect newest dlkm work dir if not explicitly passed
    out_root = os.path.join(os.path.dirname(args.ws), "out")
    if args.vd_dir is None or args.od_dir is None:
        candidates = sorted(
            glob.glob(os.path.join(out_root, "*-work")),
            key=os.path.getmtime,
            reverse=True,
        )
        for c in candidates:
            vd_c = os.path.join(c, "vendor_dlkm/lib/modules")
            od_c = os.path.join(c, "odm_dlkm/lib/modules")
            if os.path.isdir(vd_c) and os.path.isdir(od_c):
                args.vd_dir = args.vd_dir or vd_c
                args.od_dir = args.od_dir or od_c
                break

    errors = []

    # 1. Pure GKI check (never edit the GKI tree)
    gki_dirty = subprocess.check_output(["git", "-C", k_src, "status", "--porcelain"], text=True).strip()
    if gki_dirty and not args.allow_dirty_gki:
        errors.append(f"{os.path.basename(k_src)} is dirty (GKI must NEVER be edited):\n{gki_dirty}")

    # 2. Load official GKI abi.stg, Module.symvers, vmlinux.symvers, and protected GKI symbols
    abi_crcs = load_abi_stg(os.path.join(k_src, "gki/aarch64/abi.stg"))
    mods_bzl = os.path.join(k_src, "modules.bzl")
    if "_COMMON_UNPROTECTED_MODULES_LIST" not in open(mods_bzl).read():
        mods_bzl = os.path.join(k_src, "bazel/modules_private.bzl")
    unprotected = load_unprotected_gki_mods(mods_bzl)

    vmlinux_syms = {}
    for line in open(os.path.join(k_dir, "vmlinux.symvers")):
        p = line.strip().split("\t")
        if len(p) >= 2:
            vmlinux_syms[p[1]] = int(p[0], 16)

    gki_syms = {}
    protected_syms = set()
    for line in open(os.path.join(k_dir, "Module.symvers")):
        p = line.strip().split("\t")
        if len(p) >= 3:
            gki_syms[p[1]] = (int(p[0], 16), p[2])
            if p[2] != "vmlinux" and p[2] not in unprotected:
                protected_syms.add(p[1])

    build_vs_abi = [
        (s, hex(c), hex(gki_syms[s][0]))
        for s, c in abi_crcs.items()
        if s in gki_syms and gki_syms[s][0] != c
    ]
    if build_vs_abi:
        errors.append(f"GKI build Module.symvers differs from abi.stg on {len(build_vs_abi)} symbols: {build_vs_abi[:5]}")

    dirs = {}
    for part, d in [("vendor_boot", args.vb_dir), ("vendor_dlkm", args.vd_dir), ("odm_dlkm", args.od_dir)]:
        if d and os.path.isdir(d):
            dirs[part] = d
        else:
            errors.append(f"Missing module directory for {part}: {d}")

    all_data = {}
    provider = {}
    vb_provider = {}
    bad_vm = []
    diff_vm = []
    prot_hits = []
    counts = {}

    for part, d in dirs.items():
        kos = sorted(f for f in os.listdir(d) if f.endswith(".ko"))
        counts[part] = len(kos)
        check_load_and_dep(part, d, errors)
        for f in kos:
            exps, wimps, icrcs, vm = parse_ko(os.path.join(d, f))
            all_data[(part, f)] = (exps, wimps, icrcs)
            if args.strict_vermagic or want_kmi is None:
                if vm != want_vm:
                    bad_vm.append((part, f, vm))
            else:
                if parse_vermagic(vm) != want_kmi:
                    bad_vm.append((part, f, vm))
                elif vm != want_vm:
                    diff_vm.append((part, f, vm))
            for sym, c in exps.items():
                provider[sym] = (f"{part}/{f}", c)
                if part == "vendor_boot":
                    vb_provider[sym] = (f, c)
                if sym in protected_syms:
                    prot_hits.append((part, f, sym))

    # vendor_boot standalone closure
    vb_unres = []
    vb_crc_bad = []
    for (part, f), (_, wimps, icrcs) in all_data.items():
        if part != "vendor_boot":
            continue
        for sym, wc in icrcs.items():
            if sym in vmlinux_syms:
                hc = vmlinux_syms[sym]
            elif sym in vb_provider:
                hc = vb_provider[sym][1]
            elif sym in wimps:
                continue
            else:
                vb_unres.append((f, sym))
                continue
            if hc != wc:
                vb_crc_bad.append((f, sym, hex(wc), hex(hc)))

    # Full closure + ABI + non-KMI vmlinux check
    unres, crc_bad, abi_bad, non_kmi = [], [], [], []
    for (part, f), (_, wimps, icrcs) in all_data.items():
        for sym, wc in icrcs.items():
            if sym in gki_syms:
                hc = gki_syms[sym][0]
                if gki_syms[sym][1] == "vmlinux" and sym not in abi_crcs:
                    non_kmi.append((part, f, sym))
                if sym in abi_crcs and wc != abi_crcs[sym]:
                    abi_bad.append((part, f, sym, hex(wc), hex(abi_crcs[sym])))
            elif sym in provider:
                hc = provider[sym][1]
            elif sym in wimps:
                continue
            else:
                unres.append((part, f, sym))
                continue
            if hc != wc:
                crc_bad.append((part, f, sym, hex(wc), hex(hc)))

    vm_gate = "Wrong vermagic (strict)         " if args.strict_vermagic else "Wrong KMI/vermagic flags        "
    vm_extra = f" (exact-vermagic diffs: {len(diff_vm)})" if diff_vm and not args.strict_vermagic else ""
    vm_fail = "WRONG VERMAGIC" if args.strict_vermagic else "WRONG KMI/VERMAGIC"

    print(f"GKI release : {kver}")
    print(f"ABI symbols : {len(abi_crcs)} (build vs abi.stg mismatches: {len(build_vs_abi)})")
    print(f"Modules     : {sum(counts.values())} ({counts})")
    print(f"  1. Pure GKI ({os.path.basename(k_src)} clean){'':<8}: {'PASS' if not gki_dirty else 'DIRTY'}")
    print(f"  2. {vm_gate}: {len(bad_vm)}{vm_extra}")
    print(f"  3. CONFIG_MODULE_SIG_PROTECT hits  : {len(prot_hits)}")
    print(f"  4. vendor_boot standalone unres/crc: {len(vb_unres)} / {len(vb_crc_bad)}")
    print(f"  5. Full runtime closure unres/crc  : {len(unres)} / {len(crc_bad)}")
    print(f"  6. Official abi.stg CRC mismatches : {len(abi_bad)}")
    print(f"  7. Non-KMI unlisted vmlinux imports: {len(non_kmi)}")
    print(f"  8. modules.dep/load & other errors : {len(errors)}")

    if diff_vm and not args.strict_vermagic:
        alt_vms = sorted({vm for _, _, vm in diff_vm})
        print(
            f"\n[INFO] {len(diff_vm)} modules differ in exact vermagic string "
            f"(KMI + flags match; pass --strict-vermagic to enforce exact match):"
        )
        for avm in alt_vms[:10]:
            cnt = sum(1 for _, _, vm in diff_vm if vm == avm)
            print(f"  - {avm} ({cnt} modules)")

    for label, items in [
        (vm_fail, bad_vm),
        ("PROTECTED GKI EXPORT COLLISION", prot_hits),
        ("VENDOR_BOOT UNRESOLVED", vb_unres),
        ("VENDOR_BOOT CRC MISMATCH", vb_crc_bad),
        ("FULL CLOSURE UNRESOLVED", unres),
        ("FULL CLOSURE CRC MISMATCH", crc_bad),
        ("ABI.STG CRC MISMATCH", abi_bad),
        ("NON-KMI VMLINUX SYMBOL", non_kmi),
    ]:
        if items:
            print(f"\n[FAIL] {label} ({len(items)}):", file=sys.stderr)
            for x in items[:20]:
                print(" ", x, file=sys.stderr)
            errors.append(f"{label}: {len(items)}")

    if errors:
        print("\n[FAIL] Errors:", file=sys.stderr)
        for e in errors:
            print("  -", e, file=sys.stderr)
        sys.exit(1)

    print("\nALL KMI/ABI SAFEGUARDS PASSED.")


if __name__ == "__main__":
    main()

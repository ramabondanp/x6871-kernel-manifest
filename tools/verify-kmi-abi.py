#!/usr/bin/env python3
"""Verify X6871 vendor/odm/recovery kernel modules against pure upstream GKI KMI/ABI.

Safeguards enforced (exit non-zero on any failure):
  1. Pure GKI check: warns/fails if kernel-6.12 has local edits (--allow-dirty-gki to override).
  2. Vermagic check: every .ko across vendor_boot/vendor_dlkm/odm_dlkm matches the built GKI release.
  3. Official GKI ABI check: 0 CRC mismatches against kernel-6.12/gki/aarch64/abi.stg.
  4. Trimmed-GKI check: 0 imports of unlisted (non-KMI) vmlinux symbols.
  5. CONFIG_MODULE_SIG_PROTECT check: 0 exports colliding with protected GKI system_dlkm modules.
  6. Symbol & CRC closure:
       - vendor_boot standalone (vs vmlinux + vendor_boot only)
       - full runtime closure (vendor_boot + vendor_dlkm + odm_dlkm vs vmlinux + system_dlkm)
  7. modules.dep / modules.load sanity checks (no dangling entries, usb_dp_selector -> mediatek_drm_v1).

Usage:
  ./tools/verify-kmi-abi.py
  ./tools/verify-kmi-abi.py --ws /serverhive1/ramabondanp/x6871-clean/ws \\
      --vb-dir /serverhive1/ramabondanp/tmp/vbwork-twrp/build/unzip_boot/root.1/lib/modules \\
      --vd-dir /serverhive1/ramabondanp/x6871-clean/out/v19-kmi6-work/vendor_dlkm/lib/modules \\
      --od-dir /serverhive1/ramabondanp/x6871-clean/out/v19-kmi6-work/odm_dlkm/lib/modules
"""

import argparse
import glob
import os
import re
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

    vermagic = subprocess.check_output(["modinfo", "-F", "vermagic", path], text=True).strip()
    return exports, weak_imports, imp_crcs, vermagic


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
    for load_name in ("modules.load", "modules.load.recovery"):
        lp = os.path.join(mod_dir, load_name)
        if not os.path.exists(lp):
            continue
        for line in open(lp):
            entry = line.strip()
            if not entry or entry.startswith("#"):
                continue
            bn = os.path.basename(entry)
            if bn not in kos:
                errors.append(f"{part}/{load_name}: dangling entry {entry}")

    dep_path = os.path.join(mod_dir, "modules.dep")
    if os.path.exists(dep_path):
        dep_lines = open(dep_path).read().splitlines()
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
    ap = argparse.ArgumentParser(description="Verify X6871 modules against pure GKI KMI/ABI.")
    ap.add_argument("--ws", default="/serverhive1/ramabondanp/x6871-clean/ws")
    ap.add_argument(
        "--vb-dir",
        default="/serverhive1/ramabondanp/tmp/vbwork-twrp/build/unzip_boot/root.1/lib/modules",
    )
    ap.add_argument("--vd-dir", default=None, help="vendor_dlkm/lib/modules directory")
    ap.add_argument("--od-dir", default=None, help="odm_dlkm/lib/modules directory")
    ap.add_argument("--allow-dirty-gki", action="store_true")
    args = ap.parse_args()

    k_src = os.path.join(args.ws, "kernel-6.12")
    bases = sorted(
        glob.glob(f"{args.ws}/out_bazel/*/execroot/_main/bazel-out/*/bin/kernel_device_modules-6.12"),
        key=os.path.getmtime,
        reverse=True,
    )
    if not bases:
        sys.exit(f"ERROR: no Bazel output found under {args.ws}/out_bazel")
    base = bases[0]
    k_dir = os.path.join(base, "mgk_64_k612_kernel_aarch64.user")
    m_dir = os.path.join(base, "mgk_64_k612_customer_modules_install.user")
    stgs = sorted(
        glob.glob(os.path.join(m_dir, "staging/lib/modules/6.12.*")),
        key=os.path.getmtime,
        reverse=True,
    )
    if not stgs:
        sys.exit(f"ERROR: no staging tree found under {m_dir}")
    kver = os.path.basename(stgs[0])
    want_vm = f"{kver} SMP preempt mod_unload modversions aarch64"

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

    # 1. Pure GKI check (never edit kernel-6.12)
    gki_dirty = subprocess.check_output(["git", "-C", k_src, "status", "--porcelain"], text=True).strip()
    if gki_dirty and not args.allow_dirty_gki:
        errors.append(f"kernel-6.12 is dirty (GKI must NEVER be edited):\n{gki_dirty}")

    # 2. Load official GKI abi.stg, Module.symvers, vmlinux.symvers, and protected GKI symbols
    abi_crcs = load_abi_stg(os.path.join(k_src, "gki/aarch64/abi.stg"))
    unprotected = load_unprotected_gki_mods(os.path.join(k_src, "modules.bzl"))

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
    prot_hits = []
    counts = {}

    for part, d in dirs.items():
        kos = sorted(f for f in os.listdir(d) if f.endswith(".ko"))
        counts[part] = len(kos)
        check_load_and_dep(part, d, errors)
        for f in kos:
            exps, wimps, icrcs, vm = parse_ko(os.path.join(d, f))
            all_data[(part, f)] = (exps, wimps, icrcs)
            if vm != want_vm:
                bad_vm.append((part, f, vm))
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

    print(f"GKI release : {kver}")
    print(f"ABI symbols : {len(abi_crcs)} (build vs abi.stg mismatches: {len(build_vs_abi)})")
    print(f"Modules     : {sum(counts.values())} ({counts})")
    print(f"  1. Pure GKI (kernel-6.12 clean)    : {'PASS' if not gki_dirty else 'DIRTY'}")
    print(f"  2. Wrong vermagic                  : {len(bad_vm)}")
    print(f"  3. CONFIG_MODULE_SIG_PROTECT hits  : {len(prot_hits)}")
    print(f"  4. vendor_boot standalone unres/crc: {len(vb_unres)} / {len(vb_crc_bad)}")
    print(f"  5. Full runtime closure unres/crc  : {len(unres)} / {len(crc_bad)}")
    print(f"  6. Official abi.stg CRC mismatches : {len(abi_bad)}")
    print(f"  7. Non-KMI unlisted vmlinux imports: {len(non_kmi)}")
    print(f"  8. modules.dep/load & other errors : {len(errors)}")

    for label, items in [
        ("WRONG VERMAGIC", bad_vm),
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

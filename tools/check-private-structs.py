#!/usr/bin/env python3
"""Audit mirrored private kernel structs and ack_headers.bzl integrity.

Checks:
  1. Parity of tracked mirrored private kernel struct definitions between
     out-of-tree modules and the pinned GKI tree (e.g. struct vb2_dc_buf).
  2. Absence of untracked redefinitions of high-risk internal kernel structs
     in device and vendor out-of-tree modules.
  3. Integrity and bloat check of kernel/kleaf/ack_headers.bzl (all entries
     exist in the GKI tree, and no desktop DRM/GPU headers are pulled in).
"""

import argparse
import os
import re
import sys

DESKTOP_GPU_RE = re.compile(r"^drivers/gpu/drm/(amd|i915|nouveau|radeon|xe)/")

HIGH_RISK_STRUCTS = (
    "module_sect_attrs",
    "module_notes_attrs",
    "arm_lpae_io_pgtable",
    "devfreq_governor",
    "cfs_rq",
    "binder_proc",
    "binder_thread",
)


def strip_c_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def extract_struct_body(path: str, struct_name: str) -> str:
    txt = strip_c_comments(open(path, errors="ignore").read())
    m = re.search(rf"\bstruct\s+{re.escape(struct_name)}\s*\{{", txt)
    if not m:
        raise ValueError(f"struct {struct_name} not found in {path}")
    start = m.end()
    depth = 1
    i = start
    while i < len(txt) and depth > 0:
        if txt[i] == "{":
            depth += 1
        elif txt[i] == "}":
            depth -= 1
        i += 1
    if depth != 0:
        raise ValueError(f"unterminated struct {struct_name} in {path}")
    body = txt[start : i - 1]
    fields = []
    for stmt in body.split(";"):
        norm = re.sub(r"\s+", " ", stmt).strip()
        if norm:
            fields.append(norm)
    return ";\n".join(fields)


def check_mirrored_structs(dev_tree: str, gki_tree: str, errors: list):
    oot_path = os.path.join(dev_tree, "drivers/media/platform/mtk-vcodec/mtk_vcodec_drv.h")
    gki_path = os.path.join(gki_tree, "drivers/media/common/videobuf2/videobuf2-dma-contig.c")
    oot_body = extract_struct_body(oot_path, "vb2_dc_buf")
    gki_body = extract_struct_body(gki_path, "vb2_dc_buf")
    if oot_body != gki_body:
        errors.append(
            f"struct vb2_dc_buf mismatch between {oot_path} and {gki_path}:\n"
            f"--- OOT ---\n{oot_body}\n--- GKI ---\n{gki_body}"
        )
    else:
        print("[PASS] Check 1: struct vb2_dc_buf matches GKI layout")


def in_kleaf_package(path: str, stop_dir: str) -> bool:
    cur = os.path.abspath(path)
    stop = os.path.abspath(stop_dir)
    while cur != stop:
        if os.path.isfile(os.path.join(cur, "BUILD.bazel")):
            return True
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return False


def check_untracked_structs(dev_tree: str, vnd_tree: str, errors: list):
    pat = re.compile(
        r"^\s*struct\s+(" + "|".join(re.escape(s) for s in HIGH_RISK_STRUCTS) + r")\s*\{",
        re.M,
    )
    hits = []
    roots = [
        (dev_tree, os.path.join(dev_tree, "drivers")),
        (dev_tree, os.path.join(dev_tree, "sound")),
    ]
    if os.path.isdir(vnd_tree):
        roots.append((vnd_tree, vnd_tree))
    for pkg_stop, root in roots:
        if not os.path.isdir(root):
            continue
        for dp, dns, fns in os.walk(root):
            if ".git" in dns:
                dns.remove(".git")
            if not in_kleaf_package(dp, pkg_stop):
                continue
            for fn in fns:
                if not fn.endswith((".c", ".h")):
                    continue
                p = os.path.join(dp, fn)
                txt = open(p, errors="ignore").read()
                for m in pat.finditer(txt):
                    line = txt[: m.start()].count("\n") + 1
                    hits.append(f"{p}:{line}: struct {m.group(1)}")
    if hits:
        errors.append("Untracked private kernel struct redefinitions:\n  " + "\n  ".join(hits))
    else:
        print(f"[PASS] Check 2: 0 untracked high-risk private struct redefinitions ({len(HIGH_RISK_STRUCTS)} checked)")


def check_ack_headers(dev_tree: str, gki_tree: str, errors: list):
    ack_path = os.path.join(dev_tree, "kernel/kleaf/ack_headers.bzl")
    if not os.path.isfile(ack_path):
        errors.append(f"Missing {ack_path}")
        return
    txt = open(ack_path).read()
    entries = re.findall(r'"//(?:common|kernel-[^":]+):([^"]+)"', txt)
    missing = [e for e in entries if not os.path.isfile(os.path.join(gki_tree, e))]
    desktop = [e for e in entries if DESKTOP_GPU_RE.match(e)]
    if missing:
        errors.append(f"ack_headers.bzl has {len(missing)} missing GKI headers: {missing[:10]}")
    if desktop:
        errors.append(f"ack_headers.bzl contains {len(desktop)} desktop GPU headers: {desktop[:10]}")
    if not missing and not desktop:
        print(f"[PASS] Check 3: ack_headers.bzl ({len(entries)} entries, 0 missing, 0 desktop GPU bloat)")


def main():
    home = os.path.expanduser("~")
    ap = argparse.ArgumentParser(description="Check private kernel struct parity and ack_headers.bzl integrity.")
    ap.add_argument("--kver", default=os.environ.get("KVER", "6.18"))
    ap.add_argument("--ws", default=None)
    args = ap.parse_args()

    ws = args.ws
    if not ws:
        if args.kver == "6.18":
            ws = os.path.join(home, "6.18/ws")
            if not os.path.isdir(ws):
                ws = os.path.join(home, "x6871-6.18/ws")
        else:
            ws = os.path.join(home, "x6871-kernel")

    dev_tree = os.path.join(ws, f"kernel_device_modules-{args.kver}")
    vnd_tree = os.path.join(ws, "vendor/mediatek/kernel_modules")
    gki_tree = os.path.join(ws, f"kernel-{args.kver}")
    if not os.path.isdir(gki_tree):
        gki_tree = os.path.join(ws, "common")

    errors = []
    check_mirrored_structs(dev_tree, gki_tree, errors)
    check_untracked_structs(dev_tree, vnd_tree, errors)
    check_ack_headers(dev_tree, gki_tree, errors)

    if errors:
        for e in errors:
            print(f"[FAIL] {e}", file=sys.stderr)
        sys.exit(1)
    print("\nALL PRIVATE STRUCT & HEADER CHECKS PASSED.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Stage the recovery module set from a fresh kernel build.

The packer ramdisk must never be filled from an old unpacked image: that is
how a stale panel driver once got back into a USB-replug image.  This script
takes the module list committed in tools/recovery-modules.txt, resolves every
module from the Bazel staging tree that was just built, strips debug info, and
regenerates modules.dep/alias/softdep with depmod.

Usage:
    tools/stage-recovery-modules.py \
        --staging <staging>/lib/modules/6.12.x-... \
        --list tools/recovery-modules.txt \
        --load-list tools/modules.load \
        --recovery-load-list tools/modules.load.recovery \
        --dest <packer>/build/unzip_boot/root.1/lib/modules
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile


def die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    raise SystemExit(1)


def read_names(path):
    names = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            names.append(line)
    if len(names) != len(set(names)):
        die("duplicate entry in %s" % path)
    return names


def index_modules(staging):
    """Map basename -> path.  The kernel/ copy wins over extra/ on duplicates."""
    index = {}
    for root, _dirs, files in os.walk(staging):
        for name in files:
            if not name.endswith(".ko"):
                continue
            path = os.path.join(root, name)
            prev = index.get(name)
            if prev is None:
                index[name] = path
                continue
            # mtk-socinfo.ko exists as kernel/... and extra/...; the kernel
            # install is the copy the known-good images used and the one that
            # comes from the in-tree build.  Prefer it deterministically.
            if "/kernel/" in path and "/kernel/" not in prev:
                print("[stage] duplicate %s: pakai %s" % (name, path),
                      file=sys.stderr)
                index[name] = path
            elif "/kernel/" in prev and "/kernel/" not in path:
                print("[stage] duplicate %s: pertahankan %s" % (name, prev),
                      file=sys.stderr)
            else:
                die("duplikat %s tidak bisa dipilih: %s vs %s"
                    % (name, prev, path))
    return index


def stage_modules(index, names, dest, strip):
    for name in names:
        src = index[name]
        dst = os.path.join(dest, name)
        shutil.copy2(src, dst)
        subprocess.run([strip, "--strip-debug", dst], check=True)
    return len(names)


def run_depmod(dest, version, depmod):
    parent = os.path.dirname(os.path.abspath(dest))
    tmp = tempfile.mkdtemp(prefix=".depmod-", dir=parent)
    try:
        moddir = os.path.join(tmp, "lib", "modules", version)
        os.makedirs(moddir)
        for name in os.listdir(dest):
            if name.endswith(".ko"):
                shutil.copy2(os.path.join(dest, name),
                             os.path.join(moddir, name))
        proc = subprocess.run([depmod, "-b", tmp, version],
                              text=True, capture_output=True)
        if proc.returncode:
            die("depmod gagal: " + proc.stderr.strip())
        for line in proc.stderr.splitlines():
            if "modules.builtin" not in line and "modules.order" not in line:
                print("[stage] depmod: " + line, file=sys.stderr)

        # depmod writes /lib/modules/<ver>/foo.ko.  The device ramdisk is
        # flat, so rewrite every path to /lib/modules/foo.ko.
        dep_lines = []
        with open(os.path.join(moddir, "modules.dep")) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                left, _, right = line.partition(":")
                deps = " ".join("/lib/modules/" + os.path.basename(d)
                                for d in right.split())
                dep_lines.append("/lib/modules/%s:%s"
                                 % (os.path.basename(left),
                                    (" " + deps) if deps else ""))

        copy_files = [
            "modules.dep.bin", "modules.alias", "modules.alias.bin",
            "modules.softdep", "modules.symbols", "modules.symbols.bin",
            "modules.devname", "modules.builtin.bin",
            "modules.builtin.alias.bin",
        ]
        for name in copy_files:
            src = os.path.join(moddir, name)
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(dest, name))
        with open(os.path.join(dest, "modules.dep"), "w") as f:
            f.write("\n".join(dep_lines) + "\n")
        return len(dep_lines)
    finally:
        shutil.rmtree(tmp)


def filter_load_list(src, dest, present):
    kept = []
    dropped = []
    with open(src) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line in present:
                kept.append(line)
            else:
                dropped.append(line)
    if dropped:
        print("[stage] %s: %d modul dibuang (tidak ada di build): %s"
              % (os.path.basename(src), len(dropped), ", ".join(dropped)),
              file=sys.stderr)
    with open(dest, "w") as f:
        f.write("\n".join(kept) + "\n")
    return len(kept)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--staging", required=True)
    ap.add_argument("--list", required=True)
    ap.add_argument("--dest", required=True)
    ap.add_argument("--load-list")
    ap.add_argument("--recovery-load-list")
    ap.add_argument("--strip", default="llvm-strip")
    ap.add_argument("--depmod", default="depmod")
    ap.add_argument("--version", default=None)
    args = ap.parse_args()

    if not os.path.isdir(args.staging):
        die("staging tidak ada: " + args.staging)
    version = args.version or os.path.basename(os.path.normpath(args.staging))
    if not (version.startswith("6.12.") or version.startswith("6.18.")):
        die("nama staging bukan versi kernel: " + version)

    dest_norm = os.path.normpath(args.dest)
    if not dest_norm.endswith("/lib/modules"):
        die("--dest harus berakhir dengan /lib/modules: " + args.dest)
    names = read_names(args.list)
    if not names:
        die("daftar modul kosong: " + args.list)
    staging, dest = map(os.path.realpath, (args.staging, args.dest))
    if os.path.commonpath((staging, dest)) in (staging, dest):
        die("--dest tidak boleh tumpang tindih dengan --staging")
    index = index_modules(args.staging)
    missing = [n for n in names if n not in index]
    if missing:
        die("modul tidak ada di staging: " + ", ".join(missing))
    os.makedirs(args.dest, exist_ok=True)
    for entry in os.listdir(args.dest):
        path = os.path.join(args.dest, entry)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
        else:
            shutil.rmtree(path)

    count = stage_modules(index, names, args.dest, args.strip)
    dep_count = run_depmod(args.dest, version, args.depmod)

    present = set(names)
    if args.load_list:
        n = filter_load_list(args.load_list,
                             os.path.join(args.dest, "modules.load"), present)
        print("[stage] modules.load: %d entri" % n)
    if args.recovery_load_list:
        n = filter_load_list(args.recovery_load_list,
                             os.path.join(args.dest,
                                          "modules.load.recovery"), present)
        print("[stage] modules.load.recovery: %d entri" % n)

    staged = sorted(f for f in os.listdir(args.dest) if f.endswith(".ko"))
    if staged != sorted(names):
        die("isi dest tidak sama dengan daftar modul")
    print("[stage] %d modul, modules.dep %d entri, sumber %s"
          % (count, dep_count, args.staging))


if __name__ == "__main__":
    main()

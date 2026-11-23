#!/usr/bin/env python3
"""Adapt the X6871 device-module tree for the PLAN-6.18 profile.

Run from a workspace root after `repo sync`, with the device modules checked out
at `kernel_device_modules-6.18`:

    scripts/prepare-6.18-tree.py
    scripts/prepare-6.18-tree.py --tree /path/to/kernel_device_modules-6.18

The script is idempotent and only touches the device-module repo.  It never
edits the GKI tree (`common`), which must stay pristine.
"""

import argparse
import os
import re
import shutil
import sys


def replace(path, old, new, count=1):
    with open(path) as f:
        text = f.read()
    if old not in text:
        return False
    text = text.replace(old, new, count)
    with open(path, "w") as f:
        f.write(text)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tree", default="kernel_device_modules-6.18")
    args = ap.parse_args()
    tree = os.path.abspath(args.tree)
    if not os.path.isdir(tree):
        sys.exit(f"ERROR: not a directory: {tree}")

    # 1. Root BUILD.bazel ---------------------------------------------------
    build = os.path.join(tree, "BUILD.bazel")
    with open(build) as f:
        text = f.read()
    text = text.replace("//kernel-6.12:", "//common:")
    text = text.replace("//kernel_device_modules-6.12:",
                        "//kernel_device_modules-6.18:")
    text = text.replace('name = "mgk_64_k612"', 'name = "mgk_64_k618"')
    text = text.replace("# mgk_64_k612", "# mgk_64_k618")
    with open(build, "w") as f:
        f.write(text)

    # 2. kernel/kleaf/mgk_64.bzl -------------------------------------------
    mgk64 = os.path.join(tree, "kernel/kleaf/mgk_64.bzl")
    replace(mgk64,
            'load("//kernel_device_modules-6.12:kernel/kleaf/mgk_modules.bzl",',
            'load("//kernel_device_modules-6.18:kernel/kleaf/mgk_modules.bzl",')
    replace(mgk64,
            'mgk_64_defconfig = "mgk_64_k612_defconfig"',
            'mgk_64_defconfig = "mgk_64_k618_defconfig"')

    # 3. kernel/kleaf/mgk_modules.bzl --------------------------------------
    mgkmods = os.path.join(tree, "kernel/kleaf/mgk_modules.bzl")
    replace(mgkmods,
            'load("//kernel-6.12:modules.bzl", "get_gki_modules_list", "get_kunit_modules_list")',
            'load("//common:modules.bzl", "get_gki_modules_list", "get_kunit_modules_list")')
    with open(mgkmods) as f:
        text = f.read()
    text = re.sub(r'^\s*"fs/pstore/pstore_blk\.ko",\n', "", text, flags=re.M)
    with open(mgkmods, "w") as f:
        f.write(text)

    # 4. kernel/kleaf/ack_headers.bzl --------------------------------------
    ack = os.path.join(tree, "kernel/kleaf/ack_headers.bzl")
    with open(ack) as f:
        text = f.read()
    text = text.replace('"//kernel-{}:', '"//common:')
    with open(ack, "w") as f:
        f.write(text)

    # 5. Drop mkp.ko from the runtime allowlist ----------------------------
    allow = os.path.join(tree, "kernel/kleaf/x6871_modules.bzl")
    with open(allow) as f:
        lines = f.readlines()
    kept = [l for l in lines if "drivers/misc/mediatek/mkp:mkp" not in l]
    if len(kept) != len(lines):
        with open(allow, "w") as f:
            f.writelines(kept)

    # 6. Defconfig ----------------------------------------------------------
    cfg_dir = os.path.join(tree, "arch/arm64/configs")
    old_cfg = os.path.join(cfg_dir, "mgk_64_k612_defconfig")
    new_cfg = os.path.join(cfg_dir, "mgk_64_k618_defconfig")
    if os.path.exists(old_cfg) and not os.path.exists(new_cfg):
        shutil.copy2(old_cfg, new_cfg)

    # 7. Hard-coded device-tree labels in BUILD.bazel -----------------------
    for path in (
        os.path.join(tree, "sound/soc/transsion/tran_audio_control/BUILD.bazel"),
    ):
        if os.path.exists(path):
            replace(path, "//kernel_device_modules-6.12/",
                    "//kernel_device_modules-6.18/")

    # 8. Linux 6.18 Kconfig: choice blocks use prompt, not bool/tristate ---
    for dp, dns, fns in os.walk(tree):
        dns[:] = [d for d in dns if d != ".git"]
        for fn in fns:
            if fn != "Kconfig" and not fn.startswith("Kconfig."):
                continue
            path = os.path.join(dp, fn)
            with open(path, errors="ignore") as f:
                lines = f.read().splitlines()
            changed = False
            for i, line in enumerate(lines):
                if line.strip() != "choice":
                    continue
                for j in range(i + 1, min(i + 5, len(lines))):
                    stripped = lines[j].strip()
                    if stripped.startswith('bool "') or stripped.startswith('tristate "'):
                        lines[j] = lines[j].replace('bool "', 'prompt "', 1) \
                                           .replace('tristate "', 'prompt "', 1)
                        changed = True
                        break
            if changed:
                with open(path, "w") as f:
                    f.write("\n".join(lines) + "\n")

    # 9. fake_manifest.xml --------------------------------------------------
    fm = os.path.join(tree, "fake_manifest.xml")
    if os.path.exists(fm):
        with open(fm) as f:
            text = f.read()
        text = text.replace('name="kernel-6.12" path="kernel-6.12"',
                            'name="common" path="common"')
        with open(fm, "w") as f:
            f.write(text)

    print(f"prepared 6.18 tree: {tree}")


if __name__ == "__main__":
    main()

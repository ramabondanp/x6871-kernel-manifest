#!/usr/bin/env python3
"""Drop ack_headers entries that do not exist in the pinned 6.18 GKI tree.

The 6.12 port lists 4k+ GKI headers used by MTK out-of-tree code.  Linux 6.18
moved/removed some of them; leaving the labels in `ack_headers.bzl` makes Bazel
fail with "no such target".  Run after syncing the 6.18 workspace:

    scripts/audit-6.18-ack-headers.py
    scripts/audit-6.18-ack-headers.py --gki common \
        --headers kernel_device_modules-6.18/kernel/kleaf/ack_headers.bzl
"""

import argparse
import os
import re
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gki", default="common")
    ap.add_argument("--headers",
                    default="kernel_device_modules-6.18/kernel/kleaf/"
                            "ack_headers.bzl")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    pat = re.compile(r'"//common:([^"]+)"')
    kept, missing = [], []
    with open(args.headers) as f:
        for line in f:
            m = pat.search(line)
            if not m:
                kept.append(line)
                continue
            path = m.group(1)
            if os.path.exists(os.path.join(args.gki, path)):
                kept.append(line)
            else:
                missing.append(path)

    print(f"missing in {args.gki}: {len(missing)}")
    for p in missing[:50]:
        print("  " + p)
    if len(missing) > 50:
        print(f"  ... and {len(missing) - 50} more")
    if args.apply and missing:
        with open(args.headers, "w") as f:
            f.writelines(kept)
        print(f"updated {args.headers}: {len(kept)} lines")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Index compatible string -> berkas sumber, hanya pencocokan token persis.

Berbeda dengan `grep -F`, substring seperti "tc_tcpc" tidak ikut mencocokkan
"tc_tcpc_class". Hanya string literal utuh ("...") yang dianggap.

Pakai:
    ./tools/compat-source-index.py <list-compatible.txt> <tree> [<tree> ...]

Output: "berkas:compatible" per baris (siap dipakai dt-device-table.py).
"""

import os
import re
import subprocess
import sys

TOKEN_RE = re.compile(rb'"([A-Za-z0-9_.,+\- ]{4,})"')
WANTED_EXT = (".c", ".h")  # diisi dari --ext


def main(list_path, trees, exts):
    wanted = {
        line.strip().lower() for line in open(list_path, errors="replace") if line.strip()
    }

    # 1. kumpulkan berkas yang mungkin relevan
    files = set()
    for tree in trees:
        for root, _dirs, names in os.walk(tree):
            if "/out/" in root or root.endswith("/out"):
                continue
            for n in names:
                if n.endswith(exts):
                    files.add(os.path.join(root, n))

    # 2. pindai token, cocokkan persis, hanya pada baris ber-'compatible'
    for f in sorted(files):
        try:
            data = open(f, "rb").read()
        except OSError:
            continue
        if b"," not in data:
            continue
        for line in data.splitlines():
            low = line.lower()
            if b"compatible" not in low:
                continue
            # buang pemakaian sebagai konsumen (cari node), bukan of_match
            if b"of_find_compatible" in low or b"of_device_is_compatible" in low \
                    or b"of_machine_is_compatible" in low:
                continue
            for m in TOKEN_RE.finditer(line):
                tok = m.group(1).decode("utf-8", "replace")
                if tok.lower() in wanted:
                    print(f"{f}:{tok}")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("list")
    ap.add_argument("trees", nargs="+")
    ap.add_argument("--ext", default=".c,.h", help="ekstensi dipisah koma")
    a = ap.parse_args()
    main(a.list, a.trees, tuple(x for x in a.ext.split(",") if x))

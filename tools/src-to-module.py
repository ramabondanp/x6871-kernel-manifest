#!/usr/bin/env python3
"""Peta berkas sumber -> nama modul, dari BUILD.bazel (dan Makefile sederhana).

Pakai: ./tools/src-to-module.py <tree> [<tree> ...] > map.tsv
Output TSV: berkas.c<TAB>nama_modul<TAB>BUILD.bazel
"""

import glob
import os
import re
import sys

NAME_RE = re.compile(r'name\s*=\s*"([^"]+)"')
SRCS_RE = re.compile(r"srcs\s*=\s*\[(.*?)\]", re.S)
QUOTED_RE = re.compile(r'"([^"]+)"')
OBJ_RE = re.compile(r"^obj-\$\((\w+)\)\s*\+?=\s*([\w./-]+)\.o")
Y_RE = re.compile(r"^([\w-]+)-(?:y|objs|\$\()\s*[:+]?=\s*(.+)$")


MOD_RULES = (
    "mgk_ddk_ko",
    "mgk_ddk_ext_mod",
    "kernel_module",
    "ddk_module",
    "define_mgk_ddk_ko",
)


def bazel_map(path):
    text = open(path, errors="replace").read()
    out = []
    for m in NAME_RE.finditer(text):
        name = m.group(1)
        if name in ("ddk_kconfigs", "ddk_makefile", "srcs", "hdrs"):
            continue
        head = text[max(0, m.start() - 300):m.start()]
        if not any(rule in head for rule in MOD_RULES):
            continue
        window = text[m.end():m.end() + 2000]
        sm = SRCS_RE.search(window)
        if not sm:
            continue
        for f in QUOTED_RE.findall(sm.group(1)):
            if f.endswith((".c", ".h")):
                out.append((os.path.basename(f), name, path))
    return out


def makefile_map(path):
    out = []
    text = open(path, errors="replace").read()
    d = os.path.dirname(path)
    objs = {}
    for line in text.splitlines():
        line = line.strip()
        m = OBJ_RE.match(line)
        if m:
            out.append((m.group(2) + ".c", os.path.basename(m.group(2)), path))
            continue
        m = Y_RE.match(line)
        if m:
            mod = m.group(1)
            for f in m.group(2).split():
                if f.endswith(".o"):
                    objs.setdefault(mod, []).append(f[:-2] + ".c")
    for mod, files in objs.items():
        for f in files:
            out.append((os.path.basename(f), mod, path))
    return out


def main(trees):
    seen = set()
    for tree in trees:
        for path in glob.glob(os.path.join(tree, "**", "BUILD.bazel"), recursive=True):
            for f, mod, p in bazel_map(path):
                key = (f, mod)
                if key in seen:
                    continue
                seen.add(key)
                print(f"{f}\t{mod}\t{p}")
        for path in glob.glob(os.path.join(tree, "**", "Makefile"), recursive=True):
            try:
                for f, mod, p in makefile_map(path):
                    key = (f, mod)
                    if key in seen:
                        continue
                    seen.add(key)
                    print(f"{f}\t{mod}\t{p}")
            except OSError:
                continue


if __name__ == "__main__":
    main(sys.argv[1:])

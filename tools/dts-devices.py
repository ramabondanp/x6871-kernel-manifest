#!/usr/bin/env python3
"""Ekstrak semua node yang punya 'compatible' dari DTS hasil decompile.

Pakai: ./tools/dts-devices.py base.dts frag0.dts > devices.tsv

Output TSV: path<TAB>compatible<TAB>status<TAB>file

- path       : path node (base.dts pakai prefix "/", frag0.dts dihitung
               sebagai overlay: "fragment@N/__overlay__/..." dibiarkan apa adanya
               dengan target phandle dicatat di kolom file bila perlu)
- compatible : digabung dengan '|' kalau lebih dari satu
- status     : nilai 'status' terdekat (node itu sendiri, lalu induk), kosong = okay
"""

import re
import sys

NODE_RE = re.compile(r"^\s*([A-Za-z0-9_,.\-]+)\s*(@[0-9A-Fa-f,]+)?\s*\{\s*$")
PROP_RE = re.compile(r'^\s*([A-Za-z0-9_,.\-#]+)\s*=\s*(.+);\s*$')


def split_compat(value):
    """compatible = "a", "b" atau "a\\0b" (decompile NUL) -> list."""
    vals = []
    for quoted in re.findall(r'"([^"]*)"', value):
        for part in quoted.split("\\0"):
            part = part.strip()
            if part and part not in vals:
                vals.append(part)
    return vals


def walk(path):
    with open(path, "r", errors="replace") as fh:
        text = fh.read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)

    stack = []
    root_ctx = {
        "path": "/",
        "compatible": None,
        "has_compat": False,
        "status": None,
        "parent": None,
    }
    ctxs = [root_ctx]
    nodes = [root_ctx]

    def eff_status(ctx):
        cur = ctx
        while cur is not None:
            if cur["status"]:
                return cur["status"]
            cur = cur["parent"]
        return "okay"

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("}"):
            if len(ctxs) > 1:
                ctxs.pop()
                stack.pop()
            continue
        m = NODE_RE.match(line)
        if m:
            name = m.group(1) + (m.group(2) or "")
            stack.append(name)
            ctx = {
                "path": "/" + "/".join(stack),
                "compatible": None,
                "has_compat": False,
                "status": None,
                "parent": ctxs[-1],
            }
            ctxs.append(ctx)
            nodes.append(ctx)
            continue
        m = PROP_RE.match(line)
        if m:
            key, val = m.group(1), m.group(2)
            if key == "compatible":
                vals = split_compat(val)
                ctxs[-1]["compatible"] = "|".join(vals) if vals else None
                ctxs[-1]["has_compat"] = True
            elif key == "status":
                vals = split_compat(val)
                ctxs[-1]["status"] = vals[0] if vals else None
            continue

    return [
        (node["path"], node["compatible"], eff_status(node))
        for node in nodes
        if node["has_compat"]
    ]


if __name__ == "__main__":
    for fn in sys.argv[1:]:
        for path, compat, status in walk(fn):
            print(f"{path}\t{compat}\t{status}\t{fn}")

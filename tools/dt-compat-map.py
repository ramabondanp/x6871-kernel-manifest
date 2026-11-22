#!/usr/bin/env python3
"""Petakan compatible string DT -> modul .ko yang mengklaimnya.

Sumber pemetaan: alias `of:N*T*C<compatible>` di dalam .ko (modinfo), jadi
hasilnya otoritatif: itu memang driver yang akan bind.

Pakai:
    ./tools/dt-compat-map.py <dir-ko> [<dir-ko> ...] > map.tsv

Output TSV: compatible<TAB>modul<TAB>dir-asal
"""

import glob
import os
import subprocess
import sys

CACHE = {}


def aliases(path):
    if path in CACHE:
        return CACHE[path]
    text = subprocess.run(
        ["strings", "-a", path], capture_output=True
    ).stdout.decode("utf-8", "replace")
    name = None
    comps = []
    for line in text.splitlines():
        if line.startswith("name=") and name is None:
            name = line[5:]
        elif line.startswith("alias=of:"):
            rest = line[len("alias=of:"):]
            # of:NxxxTyyyCcompatible  -> ambil setelah 'C' pertama sesudah 'T'
            t = rest.find("T")
            if t < 0:
                continue
            c = rest.find("C", t)
            if c < 0:
                continue
            comp = rest[c + 1:]
            if comp:
                comps.append(comp)
    CACHE[path] = (name, sorted(set(comps)))
    return CACHE[path]


def main(dirs):
    seen = {}
    for d in dirs:
        for p in sorted(glob.glob(os.path.join(d, "*.ko"))):
            name, comps = aliases(p)
            if not name:
                name = os.path.basename(p)[:-3]
            for comp in comps:
                seen.setdefault(comp, []).append((name, d))
    for comp in sorted(seen):
        for name, d in seen[comp]:
            print(f"{comp}\t{name}\t{d}")


if __name__ == "__main__":
    main(sys.argv[1:])

#!/usr/bin/env python3
"""Bandingkan .ko stock vs .ko hasil build sendiri, per section + simbol + relokasi.

Dipakai untuk membuktikan apakah modul stock identik dengan hasil build kita
(docs/PRETEST.md §26). Modul yang "identik" di sini bukan cuma .text sama, tapi
seluruh section yang dimuat, tabel simbol, relokasi section kode, dan modinfo.

Contoh:

    ./tools/stock-vs-src.py \
        /path/stock/lib/modules/6.12.38-android16-5-g2c4fd33ae6d8-4k \
        /path/src/lib/modules/6.12.38-android16-5-g2c4fd33ae6d8-4k

Butuh toolchain silang: aarch64-linux-gnu-{objcopy,readelf,objdump}.
"""

import argparse
import glob
import hashlib
import os
import subprocess
import sys

SECS = (
    ".text",
    ".init.text",
    ".exit.text",
    ".rodata",
    ".rodata.str1.1",
    ".rodata.str1.8",
    ".rodata.cst16",
    ".rodata.cst32",
    ".data",
    ".bss",
    "__versions",
    ".gnu.linkonce.this_module",
)

CODE_SECS = (
    ".text",
    ".init.text",
    ".exit.text",
    ".hyp.text",
    ".text.unlikely",
    ".altinstr_replacement",
    ".__ex_table",
    ".fixup",
)

MODINFO_KEYS = (
    "name",
    "depends",
    "license",
    "vermagic",
    "description",
    "alias",
    "author",
    "intree",
)


def run(cmd, binary=False):
    out = subprocess.run(cmd, capture_output=True).stdout
    return out if binary else out.decode("utf-8", "replace")


def section_bytes(path, section):
    return run(
        [
            "aarch64-linux-gnu-objcopy",
            "-O",
            "binary",
            f"--only-section={section}",
            path,
            "/dev/stdout",
        ],
        binary=True,
    )


def modinfo(path):
    """Dict key -> daftar nilai (alias bisa lebih dari satu)."""
    out = {}
    for line in run(["strings", "-a", path]).splitlines():
        key, sep, value = line.partition("=")
        if sep and key in MODINFO_KEYS:
            out.setdefault(key, []).append(value)
    return {k: sorted(v) for k, v in out.items()}


def section_names(path):
    """Indeks section (string, mis. '34') -> nama section."""
    out = {}
    for line in run(["aarch64-linux-gnu-readelf", "-SW", path]).splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0].startswith("["):
            idx = parts[0].strip("[]")
            if "]" in parts[1]:  # format "[ 1] nama"
                name = parts[2]
            else:
                name = parts[1]
            out[idx] = name
    return out


def symbols(path):
    """name -> (section, offset, size, type, bind) untuk simbol global."""
    secs = section_names(path)
    out = {}
    for line in run(["aarch64-linux-gnu-readelf", "-sW", path]).splitlines():
        parts = line.split()
        if len(parts) < 8 or not parts[0].rstrip(":").isdigit():
            continue
        value, size, kind, bind, _vis, ndx, name = parts[1:8]
        if kind in ("SECTION", "FILE") or name.startswith("$"):
            continue
        if bind == "LOCAL":
            continue
        out[name] = (secs.get(ndx, ndx), int(value, 16), size, kind, bind)
    return out


def code_relocs(path):
    """Hash relokasi, dibatasi section kode (relokasi debug diabaikan)."""
    keep = []
    current = None
    for line in run(["aarch64-linux-gnu-objdump", "-r", path]).splitlines():
        if line.startswith("RELOCATION RECORDS FOR ["):
            current = line.split("[")[1].rstrip("]")
            if current in CODE_SECS:
                keep.append(line)
            continue
        if current in CODE_SECS:
            keep.append(line)
    return hashlib.sha256("\n".join(keep).encode()).hexdigest()


def compare(stock, src, verbose=False, keep_vermagic=False):
    names = sorted(
        os.path.basename(p)
        for p in glob.glob(os.path.join(stock, "*.ko"))
        if os.path.exists(os.path.join(src, os.path.basename(p)))
    )

    identical, report = [], {}
    for name in names:
        a = os.path.join(stock, name)
        b = os.path.join(src, name)
        problems = [s for s in SECS if section_bytes(a, s) != section_bytes(b, s)]
        ma, mb = modinfo(a), modinfo(b)
        if not keep_vermagic:
            ma.pop("vermagic", None)
            mb.pop("vermagic", None)
        if ma != mb:
            keys = sorted(k for k in set(ma) | set(mb) if ma.get(k) != mb.get(k))
            problems.append(f"modinfo({','.join(keys)})")
        sa, sb = symbols(a), symbols(b)
        if sa != sb:
            diff = [n for n in set(sa) | set(sb) if sa.get(n) != sb.get(n)]
            problems.append(f"simbol({len(diff)}): {', '.join(sorted(diff)[:5])}")
        elif code_relocs(a) != code_relocs(b):
            problems.append("relokasi-kode")
        if problems:
            report[name] = problems
        else:
            identical.append(name)

    print(f"modul yang ada di kedua sisi: {len(names)}")
    print(f"identik (section+simbol+relokasi+modinfo): {len(identical)}")
    for name, problems in report.items():
        print(f"  BEDA {name}: {'; '.join(problems)}")
    if verbose:
        for name in identical:
            print(f"  sama {name}")
    return 0 if not report else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("stock", help="direktori .ko stock")
    ap.add_argument("src", help="direktori .ko hasil build")
    ap.add_argument("-v", "--verbose", action="store_true", help="tampilkan modul yang sama")
    ap.add_argument(
        "--vermagic",
        action="store_true",
        help="ikut bedakan vermagic (default: diabaikan, karena localversion build bisa beda)",
    )
    args = ap.parse_args()
    return compare(args.stock, args.src, args.verbose, args.vermagic)


if __name__ == "__main__":
    sys.exit(main())

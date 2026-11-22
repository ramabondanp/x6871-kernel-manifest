#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""
Pre-flight comparison of built kernel modules against the stock firmware .ko
set.

This is a static simulation of module load and a behavioural comparison.  It
does not execute kernel code; it verifies the properties the kernel loader and
other modules rely on, and compares the external call set of every function
that exists in both builds.

Checks
------
pair:
  * exported symbols (name, type, bind, size)
  * imported symbols
  * modinfo aliases / depends / license / description
  * section sizes (.text/.rodata/.data/.bss)
  * per-function external symbol sets (objdump relocations)
  * stack frame sizes

global:
  * duplicate exports inside the staging set
  * exports that collide with vmlinux
  * unresolved imports (staging modules + vmlinux Module.symvers)
  * modversions CRC mismatches between importer and exporter
  * vermagic consistency
"""

import argparse
import json
import os
import re
import struct
import subprocess
import sys
from collections import defaultdict

INTERNAL_EXPORTS = (
    "__this_module",
    "__start_alloc_tags",
    "__stop_alloc_tags",
    "cleanup_module",
    "init_module",
    "__llvm_fs_discriminator__",
    "____versions",
    "____version_ext_crcs",
    "____version_ext_names",
)

INTERNAL_PREFIXES = (
    "__UNIQUE_ID_",
    "_note_",
    "__crc_",
    "__ksymtab_",
    "__kstrtab_",
    "__kcrctab_",
    "__mod_",
    "__param_",
    "__mcount_loc",
    "__patchable_function_entries",
)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout


def is_internal(name):
    return name in INTERNAL_EXPORTS or name.startswith(INTERNAL_PREFIXES)


def parse_symbols(path):
    """Return list of dicts: name, value, size, type, bind, ndx."""
    out = run(["readelf", "-sW", path])
    syms = []
    pat = re.compile(
        r"^\s*(\d+):\s+([0-9a-fA-F]+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*(.*)$"
    )
    for line in out.splitlines():
        m = pat.match(line)
        if not m:
            continue
        _num, value, size, stype, bind, _vis, ndx, name = m.groups()
        syms.append(
            {
                "name": name.strip(),
                "value": int(value, 16),
                "size": int(size),
                "type": stype,
                "bind": bind,
                "ndx": ndx,
            }
        )
    return syms


def ksymtab_names(syms):
    """Names that have a __ksymtab_<name> entry, i.e. real EXPORT_SYMBOL."""
    names = set()
    for s in syms:
        n = s["name"]
        if n.startswith("__ksymtab_") and n != "__ksymtab_strings":
            names.add(n[len("__ksymtab_") :])
    return names


def exports(syms):
    """Real exports only: GLOBAL defined symbols with a __ksymtab entry."""
    ksym = ksymtab_names(syms)
    out = {}
    for s in syms:
        if s["bind"] != "GLOBAL" or s["ndx"] == "UND" or not s["name"]:
            continue
        if s["name"] not in ksym or is_internal(s["name"]):
            continue
        out[s["name"]] = s
    return out


def global_defs(syms):
    """All GLOBAL defined symbols, exported or not (code surface comparison)."""
    out = {}
    for s in syms:
        if s["bind"] != "GLOBAL" or s["ndx"] == "UND" or not s["name"]:
            continue
        if is_internal(s["name"]):
            continue
        out[s["name"]] = s
    return out


def imports(syms):
    return {s["name"] for s in syms if s["ndx"] == "UND" and s["name"]}


def parse_sections(path):
    out = run(["readelf", "-SW", path])
    secs = {}
    pat = re.compile(
        r"^\s*\[\s*(\d+)\]\s+(\S+)\s+(\S+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)"
    )
    for line in out.splitlines():
        m = pat.match(line)
        if not m:
            continue
        idx, name, stype, addr, off, size = m.groups()
        secs[name] = {
            "index": int(idx),
            "type": stype,
            "addr": int(addr, 16),
            "offset": int(off, 16),
            "size": int(size, 16),
        }
    return secs


def modinfo(path, field):
    try:
        return run(["modinfo", "-F", field, path]).strip()
    except subprocess.CalledProcessError:
        return ""


def modinfo_list(path, field):
    txt = modinfo(path, field)
    return sorted(x for x in txt.splitlines() if x)


def import_crcs(path):
    out = run(["modprobe", "--dump-modversions", path])
    crcs = {}
    for line in out.splitlines():
        m = re.match(r"^(0x[0-9a-fA-F]+)\s+(\S+)$", line.strip())
        if m:
            crcs[m.group(2)] = int(m.group(1), 16)
    return crcs


def _elf_sections(path):
    """Minimal ELF64 section reader: returns list of {name,name_off,offset,size,index}."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != b"\x7fELF" or data[4] != 2:
        raise ValueError("not ELF64: " + path)
    e_shoff = struct.unpack_from("<Q", data, 0x28)[0]
    e_shentsize = struct.unpack_from("<H", data, 0x3A)[0]
    e_shnum = struct.unpack_from("<H", data, 0x3C)[0]
    e_shstrndx = struct.unpack_from("<H", data, 0x3E)[0]
    raw = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sh_name, sh_type = struct.unpack_from("<II", data, off)
        sh_offset, sh_size = struct.unpack_from("<QQ", data, off + 0x18)
        raw.append(
            {
                "index": i,
                "name_off": sh_name,
                "type": sh_type,
                "offset": sh_offset,
                "size": sh_size,
            }
        )
    strtab = raw[e_shstrndx]
    names = data[strtab["offset"] : strtab["offset"] + strtab["size"]]
    for s in raw:
        end = names.find(b"\0", s["name_off"])
        s["name"] = names[s["name_off"] : end].decode(errors="replace")
    return data, raw


def export_crcs(path, syms):
    """Read __crc_<sym> values from the module's __kcrctab section."""
    data, secs = _elf_sections(path)
    by_index = {s["index"]: s for s in secs}
    crcs = {}
    for s in syms:
        if not s["name"].startswith("__crc_") or s["ndx"] == "UND":
            continue
        sec = by_index.get(int(s["ndx"]))
        if not sec:
            continue
        off = sec["offset"] + s["value"]
        if off + 4 > len(data):
            continue
        crcs[s["name"][6:]] = struct.unpack_from("<I", data, off)[0]
    return crcs


def parse_callsets(path):
    """Map function name -> set of undefined symbols it references.

    Uses objdump relocation annotations.  Only undefined symbols are kept, so
    local helpers and section references are ignored.
    """
    syms = parse_symbols(path)
    und = imports(syms)
    out = run(["aarch64-linux-gnu-objdump", "-dr", "--no-show-raw-insn", path])
    cur = None
    calls = defaultdict(set)
    for line in out.splitlines():
        m = re.match(r"^([0-9a-f]+) <([^>]+)>:", line)
        if m:
            cur = m.group(2)
            calls[cur]  # create entry
            continue
        if cur is None:
            continue
        m = re.search(r"R_AARCH64_\S+\s+(\S+)", line)
        if not m:
            continue
        sym = m.group(1).split("+")[0]
        if sym in und:
            calls[cur].add(sym)
    return {k: sorted(v) for k, v in calls.items()}


def stack_frames(path):
    """Return function -> maximum sp subtraction seen in its prologue/body."""
    out = run(["aarch64-linux-gnu-objdump", "-d", "--no-show-raw-insn", path])
    cur = None
    frames = {}
    for line in out.splitlines():
        m = re.match(r"^([0-9a-f]+) <([^>]+)>:", line)
        if m:
            cur = m.group(2)
            frames.setdefault(cur, 0)
            continue
        if cur is None:
            continue
        m = re.search(r"\bsub\s+sp,\s*sp,\s*#(0x[0-9a-f]+|\d+)", line)
        if m:
            val = int(m.group(1), 0)
            frames[cur] = max(frames[cur], val)
    return frames


def compare_pair(built, fw):
    bsyms = parse_symbols(built)
    fsyms = parse_symbols(fw)
    bexp, fexp = exports(bsyms), exports(fsyms)
    bglob, fglob = global_defs(bsyms), global_defs(fsyms)
    bimp, fimp = imports(bsyms), imports(fsyms)

    exp_missing = sorted(set(fexp) - set(bexp))
    exp_extra = sorted(set(bexp) - set(fexp))
    exp_changed = []
    for name in sorted(set(bexp) & set(fexp)):
        b, f = bexp[name], fexp[name]
        if b["type"] != f["type"] or b["size"] != f["size"]:
            exp_changed.append(
                {
                    "name": name,
                    "built": {"type": b["type"], "size": b["size"]},
                    "fw": {"type": f["type"], "size": f["size"]},
                }
            )

    imp_missing = sorted(fimp - bimp)
    imp_extra = sorted(bimp - fimp)

    bsecs = parse_sections(built)
    fsecs = parse_sections(fw)
    sec_diff = {}
    for sec in (".text", ".init.text", ".rodata", ".data", ".bss"):
        b = bsecs.get(sec, {}).get("size", 0)
        f = fsecs.get(sec, {}).get("size", 0)
        if b or f:
            sec_diff[sec] = {"built": b, "fw": f}

    # call sets
    bcall = parse_callsets(built)
    fcall = parse_callsets(fw)
    common = sorted(set(bcall) & set(fcall))
    call_diff = []
    for fn in common:
        missing = sorted(set(fcall[fn]) - set(bcall[fn]))
        extra = sorted(set(bcall[fn]) - set(fcall[fn]))
        if missing or extra:
            call_diff.append({"function": fn, "fw_only": missing, "built_only": extra})
    fn_missing = sorted(set(fcall) - set(bcall))
    fn_extra = sorted(set(bcall) - set(fcall))

    bframes = stack_frames(built)
    big_stack = sorted(
        ((n, s) for n, s in bframes.items() if s >= 1024), key=lambda x: -x[1]
    )

    return {
        "built": built,
        "fw": fw,
        "exports": {
            "built_count": len(bexp),
            "fw_count": len(fexp),
            "missing_in_built": exp_missing,
            "extra_in_built": exp_extra,
            "changed": exp_changed,
        },
        "global_symbols": {"built_count": len(bglob), "fw_count": len(fglob)},
        "imports": {
            "built_count": len(bimp),
            "fw_count": len(fimp),
            "fw_only": imp_missing,
            "built_only": imp_extra,
        },
        "modinfo": {
            "aliases": {
                "built": modinfo_list(built, "alias"),
                "fw": modinfo_list(fw, "alias"),
            },
            "depends": {
                "built": modinfo_list(built, "depends"),
                "fw": modinfo_list(fw, "depends"),
            },
            "license": {"built": modinfo(built, "license"), "fw": modinfo(fw, "license")},
            "description": {
                "built": modinfo(built, "description"),
                "fw": modinfo(fw, "description"),
            },
        },
        "sections": sec_diff,
        "callgraph": {
            "common_functions": len(common),
            "functions_only_in_fw": fn_missing,
            "functions_only_in_built": fn_extra,
            "diffs": call_diff,
        },
        "stack_frames_over_1k": big_stack,
    }


def parse_symvers(path):
    """Return symbol -> crc from a Module.symvers file."""
    out = {}
    if not path or not os.path.exists(path):
        return out
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    out[parts[1]] = int(parts[0], 16)
                except ValueError:
                    pass
    return out


def global_checks(module_paths, symvers_path):
    all_syms = {p: parse_symbols(p) for p in module_paths}
    all_exp = {}
    all_crc = {}
    all_imp_crc = {}
    for p in module_paths:
        all_exp[p] = exports(all_syms[p])
        all_crc[p] = export_crcs(p, all_syms[p])
        all_imp_crc[p] = import_crcs(p)

    name_to_modules = defaultdict(list)
    for p, exp in all_exp.items():
        for name in exp:
            name_to_modules[name].append(os.path.basename(p))
    duplicates = {n: m for n, m in name_to_modules.items() if len(m) > 1}

    kernel_crc = parse_symvers(symvers_path)
    kernel_exports = set(kernel_crc)
    collisions = sorted(set(name_to_modules) & kernel_exports)

    unresolved = {}
    crc_mismatch = []
    for p in module_paths:
        miss = []
        for sym in sorted(imports(all_syms[p])):
            exporter = None
            if sym in name_to_modules:
                candidates = [q for q in module_paths if sym in all_exp[q]]
                exporter = candidates[0] if candidates else None
            if exporter is not None:
                want = all_imp_crc[p].get(sym)
                have = all_crc[exporter].get(sym)
                if want is not None and have is not None and want != have:
                    crc_mismatch.append(
                        {
                            "importer": os.path.basename(p),
                            "exporter": os.path.basename(exporter),
                            "symbol": sym,
                            "importer_crc": "%08x" % want,
                            "exporter_crc": "%08x" % have,
                        }
                    )
            elif sym in kernel_crc:
                want = all_imp_crc[p].get(sym)
                have = kernel_crc[sym]
                if want is not None and want != have:
                    crc_mismatch.append(
                        {
                            "importer": os.path.basename(p),
                            "exporter": "vmlinux",
                            "symbol": sym,
                            "importer_crc": "%08x" % want,
                            "exporter_crc": "%08x" % have,
                        }
                    )
            else:
                miss.append(sym)
        if miss:
            unresolved[os.path.basename(p)] = miss

    vermagic = defaultdict(list)
    for p in module_paths:
        vermagic[modinfo(p, "vermagic")].append(os.path.basename(p))

    return {
        "module_count": len(module_paths),
        "duplicate_exports": duplicates,
        "kernel_collisions": collisions,
        "unresolved_imports": unresolved,
        "crc_mismatches": crc_mismatch,
        "vermagic_groups": {k: v for k, v in vermagic.items() if k},
    }


def fmt_list(items, limit=12):
    if not items:
        return "none"
    if len(items) <= limit:
        return ", ".join("`%s`" % x for x in items)
    return ", ".join("`%s`" % x for x in items[:limit]) + ", ... (+%d)" % (
        len(items) - limit
    )


def pair_markdown(rep, built_root, fw_root):
    name = os.path.basename(rep["built"])
    e = rep["exports"]
    i = rep["imports"]
    cg = rep["callgraph"]
    lines = []
    lines.append("### `%s`" % name)
    lines.append("")
    lines.append("| Properti | Built | Firmware |")
    lines.append("|---|---|---|")
    lines.append(
        "| exports | %d | %d |" % (e["built_count"], e["fw_count"])
    )
    lines.append(
        "| global symbols (exported or not) | %d | %d |"
        % (
            rep["global_symbols"]["built_count"],
            rep["global_symbols"]["fw_count"],
        )
    )
    lines.append(
        "| imports | %d | %d |" % (i["built_count"], i["fw_count"])
    )
    for sec, v in rep["sections"].items():
        lines.append("| `%s` | %d | %d |" % (sec, v["built"], v["fw"]))
    lines.append(
        "| aliases | %s | %s |"
        % (
            fmt_list(rep["modinfo"]["aliases"]["built"]),
            fmt_list(rep["modinfo"]["aliases"]["fw"]),
        )
    )
    lines.append(
        "| depends | %s | %s |"
        % (
            fmt_list(rep["modinfo"]["depends"]["built"]),
            fmt_list(rep["modinfo"]["depends"]["fw"]),
        )
    )
    lines.append("")
    if e["missing_in_built"]:
        lines.append(
            "- exports hilang: %s" % fmt_list(e["missing_in_built"], 20)
        )
    if e["extra_in_built"]:
        lines.append("- exports tambahan: %s" % fmt_list(e["extra_in_built"], 20))
    obj_changed = [x for x in e["changed"] if x["built"]["type"] == "OBJECT"]
    if obj_changed:
        lines.append("- **OBJECT size/type berbeda:**")
        for x in obj_changed:
            lines.append(
                "  - `%s`: built %s/%d vs fw %s/%d"
                % (
                    x["name"],
                    x["built"]["type"],
                    x["built"]["size"],
                    x["fw"]["type"],
                    x["fw"]["size"],
                )
            )
    if i["fw_only"]:
        lines.append("- imports hanya di firmware: %s" % fmt_list(i["fw_only"], 20))
    if i["built_only"]:
        lines.append("- imports hanya di built: %s" % fmt_list(i["built_only"], 20))
    lines.append(
        "- fungsi common: %d; hanya firmware: %d; hanya built: %d"
        % (cg["common_functions"], len(cg["functions_only_in_fw"]), len(cg["functions_only_in_built"]))
    )
    if cg["diffs"]:
        lines.append("")
        lines.append("| Fungsi | Call firmware saja | Call built saja |")
        lines.append("|---|---|---|")
        for d in cg["diffs"]:
            lines.append(
                "| `%s` | %s | %s |"
                % (
                    d["function"],
                    fmt_list(d["fw_only"]),
                    fmt_list(d["built_only"]),
                )
            )
    if rep["stack_frames_over_1k"]:
        lines.append("")
        lines.append(
            "- stack frame >= 1 KiB: %s"
            % ", ".join("`%s`=%d" % (n, s) for n, s in rep["stack_frames_over_1k"])
        )
    lines.append("")
    return "\n".join(lines)


def index_ko(root):
    """Map basename -> path (supports both flat and nested staging trees)."""
    index = {}
    for dirpath, _dirs, files in os.walk(root):
        for name in sorted(files):
            if not name.endswith(".ko"):
                continue
            path = os.path.join(dirpath, name)
            prev = index.get(name)
            if prev is None or ("/kernel/" in path and "/kernel/" not in prev):
                index[name] = path
    return index


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--built", required=True, help="staging or flat built module directory")
    ap.add_argument("--fw", required=True, help="stock firmware module directory")
    ap.add_argument(
        "--modules",
        default="tran_extcon_usb,tran_fp,tnek,tkv",
        help="comma separated base names",
    )
    ap.add_argument("--symvers", default="", help="vmlinux Module.symvers")
    ap.add_argument("--json", default="", help="write machine readable report")
    ap.add_argument("--markdown", default="", help="write Markdown report")
    args = ap.parse_args()

    built_idx = index_ko(args.built)
    fw_idx = index_ko(args.fw)
    modules = [m.strip() for m in args.modules.split(",") if m.strip()]
    built_paths, fw_paths = [], []
    for m in modules:
        ko = m if m.endswith(".ko") else m + ".ko"
        if ko not in built_idx:
            sys.exit("missing built module: " + os.path.join(args.built, ko))
        if ko not in fw_idx:
            sys.exit("missing firmware module: " + os.path.join(args.fw, ko))
        built_paths.append(built_idx[ko])
        fw_paths.append(fw_idx[ko])

    pair_reports = {}
    for b, f in zip(built_paths, fw_paths):
        pair_reports[os.path.basename(b)[:-3]] = compare_pair(b, f)

    staging_paths = sorted(built_idx.values())
    glob = global_checks(staging_paths, args.symvers)

    report = {"pairs": pair_reports, "global": glob}
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(report, fh, indent=2, sort_keys=True)

    if args.markdown:
        lines = ["# Pre-flight module comparison", ""]
        lines.append(
            "Dibuat oleh `tools/ko-preflight.py`. Built: `%s`; firmware: `%s`."
            % (args.built, args.fw)
        )
        lines.append("")
        for name in modules:
            lines.append(pair_markdown(pair_reports[name], args.built, args.fw))
        lines.append("## Pemeriksaan global staging")
        lines.append("")
        lines.append(
            "Modul diperiksa: **%d**. Duplikat export: **%d**. Bentrok dengan vmlinux: **%d**. "
            "Impor tak terselesaikan: **%d** modul. CRC mismatch: **%d**. Grup vermagic: **%d**."
            % (
                glob["module_count"],
                len(glob["duplicate_exports"]),
                len(glob["kernel_collisions"]),
                len(glob["unresolved_imports"]),
                len(glob["crc_mismatches"]),
                len(glob["vermagic_groups"]),
            )
        )
        lines.append("")
        if glob["duplicate_exports"]:
            lines.append("### Duplikat export")
            for sym, mods in sorted(glob["duplicate_exports"].items()):
                lines.append("- `%s`: %s" % (sym, ", ".join(mods)))
            lines.append("")
        if glob["kernel_collisions"]:
            lines.append("### Bentrok export dengan vmlinux")
            lines.append(fmt_list(glob["kernel_collisions"], 50))
            lines.append("")
        if glob["unresolved_imports"]:
            lines.append("### Impor tak terselesaikan")
            for mod, syms in sorted(glob["unresolved_imports"].items()):
                lines.append("- `%s`: %s" % (mod, fmt_list(syms, 30)))
            lines.append("")
        if glob["crc_mismatches"]:
            lines.append("### CRC modversions tidak cocok")
            lines.append("| Importer | Exporter | Symbol | Importer CRC | Exporter CRC |")
            lines.append("|---|---|---|---|---|")
            for x in glob["crc_mismatches"]:
                lines.append(
                    "| %s | %s | `%s` | %s | %s |"
                    % (
                        x["importer"],
                        x["exporter"],
                        x["symbol"],
                        x["importer_crc"],
                        x["exporter_crc"],
                    )
                )
            lines.append("")
        lines.append("### Vermagic")
        for v, mods in sorted(glob["vermagic_groups"].items()):
            lines.append("- `%s`: %d modul" % (v, len(mods)))
        lines.append("")
        with open(args.markdown, "w") as fh:
            fh.write("\n".join(lines))

    # console summary
    for name, rep in pair_reports.items():
        e, i, cg = rep["exports"], rep["imports"], rep["callgraph"]
        print(
            "%-16s exports %3d/%-3d imports %3d/%-3d callset-diffs %2d "
            "fw-only-fn %3d stack>=1K %d"
            % (
                name,
                e["built_count"],
                e["fw_count"],
                i["built_count"],
                i["fw_count"],
                len(cg["diffs"]),
                len(cg["functions_only_in_fw"]),
                len(rep["stack_frames_over_1k"]),
            )
        )
    print(
        "global: modules=%d dup-exports=%d kernel-collisions=%d "
        "unresolved-modules=%d crc-mismatch=%d"
        % (
            glob["module_count"],
            len(glob["duplicate_exports"]),
            len(glob["kernel_collisions"]),
            len(glob["unresolved_imports"]),
            len(glob["crc_mismatches"]),
        )
    )


if __name__ == "__main__":
    main()

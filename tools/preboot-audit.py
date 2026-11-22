#!/usr/bin/env python3
"""Pre-boot audit of every module that *replaces* a stock firmware module.

ko-preflight.py compares the four ported feature modules.  This script walks
the stock firmware module set instead — one row per stock `.ko` — and checks
the built counterpart for each of them:

  * present or missing in the staging tree
  * duplicate basenames in the staging tree (they collide when the modules are
    flattened into /vendor/lib/modules, so modprobe picks one at random)
  * vermagic consistency inside the built set (a module built from another
    kernel revision cannot load at all)
  * exported/imported symbol drift, `depends` drift, .text size delta
  * loader simulation over exactly that set: unresolved imports and
    modversions CRC mismatches, ignoring weak undefined symbols (they resolve
    to 0 and never block a load)
  * hardware API census per module compared with its stock twin, to catch a
    replacement that suddenly gained mmio/regulator/gpio/clock access
  * which of them stock actually loads (modules.load / .recovery) vs merely
    ships

Usage:
    python3 tools/preboot-audit.py --built <staging/lib/modules/VER> \\
        --fw <stock lib/modules> --symvers <build>/.../Module.symvers \\
        [--json out.json] [--markdown out.md]
"""

import argparse
import collections
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load_preflight():
    spec = importlib.util.spec_from_file_location(
        "ko_preflight", os.path.join(HERE, "ko-preflight.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


KP = load_preflight()

# Imports that mean "this module touches hardware directly".
HW_APIS = {
    "ioremap": "mmio-map",
    "ioremap_wc": "mmio-map",
    "devm_ioremap": "mmio-map",
    "devm_ioremap_resource": "mmio-map",
    "of_iomap": "mmio-map",
    "readl": "mmio-rw",
    "writel": "mmio-rw",
    "readw": "mmio-rw",
    "writew": "mmio-rw",
    "regulator_enable": "regulator",
    "regulator_disable": "regulator",
    "regulator_set_voltage": "regulator",
    "regulator_set_voltage_sel": "regulator",
    "regulator_force_disable": "regulator",
    "gpio_request": "gpio",
    "devm_gpio_request": "gpio",
    "gpio_direction_output": "gpio",
    "gpio_set_value": "gpio",
    "gpiod_set_value": "gpio",
    "clk_enable": "clock",
    "clk_prepare_enable": "clock",
    "clk_set_rate": "clock",
    "pinctrl_select_state": "pinctrl",
    "dma_alloc_attrs": "dma",
    "dma_map_single": "dma",
    "request_threaded_irq": "irq",
    "request_irq": "irq",
    "spi_sync": "spi",
    "i2c_transfer": "i2c",
    "i2c_smbus_xfer": "i2c",
}


def index_modules(root):
    """basename -> path, plus the map of duplicate basenames."""
    by_name = {}
    dups = {}
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            if not f.endswith(".ko"):
                continue
            p = os.path.join(dirpath, f)
            if f in by_name:
                dups.setdefault(f, [by_name[f]]).append(p)
            else:
                by_name[f] = p
    return by_name, dups


def read_list(path):
    out = []
    if not os.path.exists(path):
        return out
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#"):
                out.append(line)
    return out


def split_imports(syms):
    """(hard imports, weak imports).  Weak undefined symbols resolve to 0."""
    hard, weak = set(), set()
    for s in syms:
        if s["ndx"] != "UND" or not s["name"]:
            continue
        if s["bind"] == "WEAK":
            weak.add(s["name"])
        else:
            hard.add(s["name"])
    return hard, weak


def hw_apis(syms):
    return {s["name"] for s in syms
            if s["ndx"] == "UND" and s["name"] in HW_APIS}


def compare(built_path, fw_path):
    """Structural comparison of one built module against its stock twin."""
    rec = {}
    try:
        b_syms = KP.parse_symbols(built_path)
        f_syms = KP.parse_symbols(fw_path)
    except Exception as exc:  # pragma: no cover
        return {"unparsable": str(exc), "status": "fail", "notes": ["unparsable"]}

    rec["vermagic_built"] = KP.modinfo(built_path, "vermagic")
    rec["vermagic_stock"] = KP.modinfo(fw_path, "vermagic")
    rec["license_same"] = KP.modinfo(built_path, "license") == \
        KP.modinfo(fw_path, "license")

    b_exp = set(KP.exports(b_syms))
    f_exp = set(KP.exports(f_syms))
    rec["exports_missing"] = sorted(f_exp - b_exp)
    rec["exports_extra"] = sorted(b_exp - f_exp)

    b_imp, b_weak = split_imports(b_syms)
    f_imp, _f_weak = split_imports(f_syms)
    rec["imports_built"] = len(b_imp)
    rec["imports_stock"] = len(f_imp)
    rec["imports_only_built"] = sorted(b_imp - f_imp)
    rec["weak_imports"] = sorted(b_weak)

    rec["depends_built"] = KP.modinfo(built_path, "depends")
    rec["depends_stock"] = KP.modinfo(fw_path, "depends")
    rec["depends_same"] = rec["depends_built"] == rec["depends_stock"]

    try:
        bt = KP.parse_sections(built_path).get(".text", {}).get("size", 0)
        ft = KP.parse_sections(fw_path).get(".text", {}).get("size", 0)
        rec["text_built"] = bt
        rec["text_stock"] = ft
        rec["text_delta_pct"] = round((bt - ft) * 100.0 / ft, 1) if ft else None
    except Exception:
        pass

    rec["hw_built"] = sorted(hw_apis(b_syms))
    rec["hw_new"] = sorted(hw_apis(b_syms) - hw_apis(f_syms))
    rec["stack_over_1k"] = sorted(
        ((n, s) for n, s in KP.stack_frames(built_path).items() if s >= 1024),
        key=lambda x: -x[1],
    )
    rec["status"] = "ok"
    rec["notes"] = []
    return rec


def classify(pairs, union_imports, expected_vermagic):
    """Decide ok/warn/fail now that the whole set is known."""
    for name, r in pairs.items():
        if r.get("unparsable"):
            continue
        notes = r["notes"]

        if r["vermagic_built"] != expected_vermagic:
            r["status"] = "fail"
            notes.append("vermagic != set: %s" % r["vermagic_built"])

        # An export that stock had and we lost only matters if something in
        # this very set imports it.
        needed = sorted(set(r["exports_missing"]) & union_imports)
        r["exports_missing_needed"] = needed
        if needed:
            r["status"] = "fail"
            notes.append("%d lost export(s) still imported: %s"
                         % (len(needed), ", ".join(needed[:4])))
        elif r["exports_missing"]:
            if r["status"] == "ok":
                r["status"] = "warn"
            notes.append("%d export(s) not re-exported (unused in set)"
                         % len(r["exports_missing"]))

        if r["exports_extra"]:
            if r["status"] == "ok":
                r["status"] = "warn"
            notes.append("%d new export(s)" % len(r["exports_extra"]))

        if not r["depends_same"]:
            if r["status"] == "ok":
                r["status"] = "warn"
            notes.append("depends %r -> %r"
                         % (r["depends_stock"], r["depends_built"]))

        if r["hw_new"]:
            if r["status"] == "ok":
                r["status"] = "warn"
            notes.append("hw api baru: %s" % ", ".join(r["hw_new"][:4]))

        if not r["license_same"]:
            if r["status"] == "ok":
                r["status"] = "warn"
            notes.append("license berbeda")


def alias_risk(built_root, built_names):
    """modules.alias entries pointing outside the built set."""
    path = None
    for dirpath, _dirs, files in os.walk(built_root):
        if "modules.alias" in files:
            path = os.path.join(dirpath, "modules.alias")
            break
    if not path:
        return None, []
    outside = set()
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith("alias "):
                continue
            m = line.rsplit(None, 1)
            if len(m) != 2:
                continue
            name = m[1].split("/")[-1]
            if not name.endswith(".ko"):
                name += ".ko"
            if name not in built_names:
                outside.add(name)
    return path, sorted(outside)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--built", required=True, help="staging lib/modules/<ver> tree")
    ap.add_argument("--fw", required=True, help="stock lib/modules directory")
    ap.add_argument("--symvers", default="", help="vmlinux Module.symvers")
    ap.add_argument("--json", default="")
    ap.add_argument("--markdown", default="")
    args = ap.parse_args()

    built_by_name, dups = index_modules(args.built)
    fw_by_name, _fw_dups = index_modules(args.fw)
    stock_modules = sorted(fw_by_name)

    load = read_list(os.path.join(args.fw, "modules.load"))
    load_rec = read_list(os.path.join(args.fw, "modules.load.recovery"))
    boot_listed = set(load) | set(load_rec)

    missing = sorted(m for m in stock_modules if m not in built_by_name)
    present = sorted(m for m in stock_modules if m in built_by_name)
    extra = sorted(m for m in built_by_name if m not in fw_by_name)

    pairs = {}
    for name in present:
        pairs[name] = compare(built_by_name[name], fw_by_name[name])

    # Vermagic the whole set must agree on: the majority of the built modules.
    hist = collections.Counter(
        KP.modinfo(p, "vermagic") for p in built_by_name.values())
    expected_vermagic = hist.most_common(1)[0][0] if hist else ""

    union_imports = set()
    for name in present:
        hard, _weak = split_imports(KP.parse_symbols(built_by_name[name]))
        union_imports |= hard

    classify(pairs, union_imports, expected_vermagic)

    load_paths = [built_by_name[m] for m in present]
    glob = KP.global_checks(load_paths, args.symvers)

    # global_checks reports every UND symbol, weak ones included; drop the
    # weak references so the loader picture matches reality.
    weak_by_module = {n: set(pairs[n].get("weak_imports", [])) for n in pairs}
    unresolved = {}
    for name, syms in glob.get("unresolved_imports", {}).items():
        real = [s for s in syms if s not in weak_by_module.get(name, set())]
        if real:
            unresolved[name] = real
    glob["unresolved_imports"] = unresolved

    alias_path, alias_outside = alias_risk(args.built, set(built_by_name))

    report = {
        "inventory": {
            "stock_modules": len(stock_modules),
            "built_modules": len(built_by_name),
            "expected_vermagic": expected_vermagic,
            "vermagic_groups": {k: v for k, v in hist.items()},
            "duplicate_basenames": dups,
            "present": len(present),
            "missing": missing,
            "boot_listed": sorted(m for m in present if m in boot_listed),
            "shipped_but_not_loaded": sorted(m for m in present
                                             if m not in boot_listed),
            "built_without_stock_twin": extra,
        },
        "pairs": pairs,
        "load_set_global": glob,
        "aliases": {
            "file": alias_path,
            "autoload_outside_build_set": alias_outside,
        },
    }

    if args.json:
        with open(args.json, "w") as fh:
            json.dump(report, fh, indent=2, sort_keys=True)

    fails = sorted(n for n, r in pairs.items() if r["status"] == "fail")
    warns = sorted(n for n, r in pairs.items() if r["status"] == "warn")

    print("universe   : %d modul stock, %d punya pengganti, %d hilang"
          % (len(stock_modules), len(present), len(missing)))
    print("vermagic   : %s (%d grup di set build)"
          % (expected_vermagic, len(hist)))
    print("duplikat   : %s" % (", ".join(sorted(dups)) or "tidak ada"))
    print("loader     : unresolved=%d crc-mismatch=%d dup-exports=%d kernel-collisions=%d"
          % (len(unresolved), len(glob.get("crc_mismatches", [])),
             len(glob.get("duplicate_exports", {})),
             len(glob.get("kernel_collisions", []))))
    print("struktural : %d fail, %d warn, %d ok"
          % (len(fails), len(warns), len(pairs) - len(fails) - len(warns)))
    if fails:
        print("FAIL       : %s" % ", ".join(fails))
    if warns:
        print("WARN       : %s" % ", ".join(warns))
    if missing:
        print("MISSING    : %s" % ", ".join(missing))
    print("extra      : %d modul build tanpa kembaran stock" % len(extra))

    if args.markdown:
        write_markdown(args.markdown, report)


def write_markdown(path, rep):
    inv = rep["inventory"]
    glob = rep["load_set_global"]
    pairs = rep["pairs"]
    lines = ["# Pre-boot audit — pengganti modul stock", ""]
    lines.append("Sumber: `tools/preboot-audit.py`. Satu baris per `.ko` stock.")
    lines.append("")
    lines.append("## Inventory")
    lines.append("")
    lines.append("| Item | Nilai |")
    lines.append("|---|---|")
    lines.append("| modul stock (`.ko` di firmware) | %d |" % inv["stock_modules"])
    lines.append("| punya pengganti di build | %d |" % inv["present"])
    lines.append("| tidak ada di build | %d |" % len(inv["missing"]))
    lines.append("| pengganti yang ada di `modules.load`/`.recovery` | %d |"
                 % len(inv["boot_listed"]))
    lines.append("| dikirim tapi tidak di-load stock | %d |"
                 % len(inv["shipped_but_not_loaded"]))
    lines.append("| modul build tanpa kembaran stock | %d |"
                 % len(inv["built_without_stock_twin"]))
    lines.append("| vermagic set build | `%s` |" % inv["expected_vermagic"])
    lines.append("| grup vermagic di set build | %d |" % len(inv["vermagic_groups"]))
    if inv["duplicate_basenames"]:
        lines.append("| **basename duplikat** | %s |"
                     % ", ".join("`%s`" % k for k in sorted(inv["duplicate_basenames"])))
    lines.append("")
    if inv["missing"]:
        lines.append("Tidak ada di build: " + ", ".join("`%s`" % m for m in inv["missing"]))
        lines.append("")

    lines.append("## Simulasi loader (set pengganti stock)")
    lines.append("")
    lines.append("| Item | Jumlah |")
    lines.append("|---|---|")
    lines.append("| modul dengan impor tak terselesaikan | %d |" % len(glob.get("unresolved_imports", {})))
    lines.append("| CRC mismatch | %d |" % len(glob.get("crc_mismatches", [])))
    lines.append("| export duplikat | %d |" % len(glob.get("duplicate_exports", {})))
    lines.append("| tabrakan simbol vmlinux | %d |" % len(glob.get("kernel_collisions", [])))
    lines.append("")
    ui = glob.get("unresolved_imports", {})
    if ui:
        lines.append("### Impor tak terselesaikan")
        lines.append("")
        for name, syms in sorted(ui.items()):
            lines.append("- `%s`: %s" % (name, ", ".join(syms[:8])))
        lines.append("")
    cm = glob.get("crc_mismatches", [])
    if cm:
        lines.append("### CRC mismatch")
        lines.append("")
        lines.append("| symbol | exporter | importer |")
        lines.append("|---|---|---|")
        for e in cm[:40]:
            lines.append("| `%s` | `%s` | `%s` |" % (e["symbol"], e["exporter"], e["importer"]))
        if len(cm) > 40:
            lines.append("| ... | %d entri lain | |" % (len(cm) - 40))
        lines.append("")

    lines.append("## Perbandingan struktural per modul")
    lines.append("")
    lines.append("| Modul | Status | Ekspor hilang (dipakai) | Ekspor hilang (total) | Ekspor baru | Impor built/stock | API hw baru | Catatan |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for name in sorted(pairs):
        r = pairs[name]
        if r.get("unparsable"):
            lines.append("| `%s` | fail | - | - | - | - | - | unparsable |" % name)
            continue
        lines.append("| `%s` | %s | %d | %d | %d | %d/%d | %s | %s |" % (
            name, r["status"],
            len(r.get("exports_missing_needed", [])),
            len(r.get("exports_missing", [])),
            len(r.get("exports_extra", [])),
            r.get("imports_built", 0), r.get("imports_stock", 0),
            ", ".join(r.get("hw_new", [])[:3]) or "-",
            "; ".join(r.get("notes", [])[:3]) or "-",
        ))
    lines.append("")

    al = rep["aliases"]
    lines.append("## Autoload di luar set build")
    lines.append("")
    if al["file"]:
        lines.append("`%s`: %d entri menunjuk modul yang tidak ada di set build."
                     % (al["file"], len(al["autoload_outside_build_set"])))
        if al["autoload_outside_build_set"]:
            lines.append("")
            lines.append(", ".join("`%s`" % x for x in al["autoload_outside_build_set"][:40]))
    else:
        lines.append("`modules.alias` tidak ditemukan di tree staging.")
    lines.append("")

    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()

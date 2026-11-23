#!/usr/bin/env python3
"""Mechanical Linux 6.13-6.18 API codemod for the X6871 out-of-tree trees.

Default is a dry run; pass --apply to edit files.  Safe, string-level
transformations are applied by default; the charger/DAPM/wakeup transforms
need --all because their call sites still need a human look.

Usage:
    scripts/port-6.18-mechanical.py                 # report only
    scripts/port-6.18-mechanical.py --apply         # transform safe classes
    scripts/port-6.18-mechanical.py --apply --all   # include risky classes
"""

import argparse
import os
import re
import sys

SAFE = ("module_import_ns", "timer_delete", "timer_container_of",
        "hrtimer_setup", "no_llseek")
RISKY = ("power_supply_reference", "dapm_rename", "wakeup_source")


def files(root):
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in (".git", "build", "out")]
        for fn in fns:
            if fn.endswith(".c"):
                yield os.path.join(dp, fn)


def transform(text, want):
    counts = {}

    def sub(name, pattern, repl, flags=0):
        nonlocal text
        text, n = re.subn(pattern, repl, text, flags=flags)
        if n:
            counts[name] = counts.get(name, 0) + n

    if "module_import_ns" in want:
        # MODULE_IMPORT_NS(FOO) -> MODULE_IMPORT_NS("FOO")
        def ns(m):
            arg = m.group(1).strip()
            if arg.startswith('"'):
                return m.group(0)
            return f'MODULE_IMPORT_NS("{arg}")'
        text, n = re.subn(r'MODULE_IMPORT_NS\(\s*([A-Za-z0-9_]+)\s*\)', ns, text)
        if n:
            counts["module_import_ns"] = n

    if "timer_delete" in want:
        sub("timer_delete", r'\bdel_timer_sync\s*\(', 'timer_delete_sync(')
        sub("timer_delete", r'\bdel_timer\s*\(', 'timer_delete(')

    if "timer_container_of" in want:
        sub("timer_container_of", r'\bfrom_timer\s*\(', 'timer_container_of(')

    if "hrtimer_setup" in want:
        # hrtimer_init(&h, clock, mode); ... h.function = fn;
        pat = re.compile(
            r'hrtimer_init\(\s*&(\w+)\s*,\s*([^,]+?)\s*,\s*([^)]+?)\s*\)\s*;\s*'
            r'(?:[^\n]*\n){0,6}?\s*\1\.function\s*=\s*([^;]+?)\s*;',
            re.M)
        def hrt(m):
            return (f'hrtimer_setup(&{m.group(1)}, {m.group(4).strip()}, '
                    f'{m.group(2).strip()}, {m.group(3).strip()});')
        text, n = pat.subn(hrt, text)
        if n:
            counts["hrtimer_setup"] = n

    if "no_llseek" in want:
        sub("no_llseek", r'^[ \t]*\.llseek\s*=\s*(?:no_llseek|noop_llseek)\s*,\s*\n',
            '', flags=re.M)

    if "power_supply_reference" in want:
        sub("power_supply_reference",
            r'\bdevm_power_supply_get_by_phandle\s*\(',
            'devm_power_supply_get_by_reference(')
        sub("power_supply_reference",
            r'\bpower_supply_get_by_phandle\s*\(',
            'power_supply_get_by_reference(')

    if "dapm_rename" in want:
        for old, new in (
                ("dapm_clock_event", "snd_soc_dapm_clock_event"),
                ("dapm_regulator_event", "snd_soc_dapm_regulator_event"),
                ("dapm_kcontrol_get_value", "snd_soc_dapm_kcontrol_get_value")):
            sub("dapm_rename", r'\b%s\s*\(' % old, new + '(')

    if "wakeup_source" in want:
        # Pair create+add into register(NULL, name), remove+destroy into unregister.
        def create(m):
            return f'wakeup_source_register(NULL, {m.group(1)})'
        sub("wakeup_source", r'\bwakeup_source_create\s*\(\s*([^);]+?)\s*\)', create)
        sub("wakeup_source", r'^[ \t]*wakeup_source_add\([^;]*\);\s*\n', '',
            flags=re.M)
        sub("wakeup_source", r'^[ \t]*wakeup_source_remove\([^;]*\);\s*\n', '',
            flags=re.M)
        sub("wakeup_source", r'\bwakeup_source_destroy\s*\(', 'wakeup_source_unregister(')

    return text, counts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("roots", nargs="*",
                    default=["kernel_device_modules-6.18",
                             "vendor/mediatek/kernel_modules"])
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    want = SAFE + (RISKY if args.all else ())

    total = {}
    changed = 0
    for root in args.roots:
        if not os.path.isdir(root):
            print(f"skip missing root: {root}")
            continue
        for path in files(root):
            with open(path, errors="surrogateescape") as f:
                text = f.read()
            new, counts = transform(text, want)
            if counts:
                for k, v in counts.items():
                    total[k] = total.get(k, 0) + v
                if new != text and args.apply:
                    with open(path, "w", errors="surrogateescape") as f:
                        f.write(new)
                    changed += 1
    print("transform hits:")
    for k in sorted(total):
        print(f"  {k}: {total[k]}")
    if args.apply:
        print(f"files changed: {changed}")
    else:
        print("dry run; pass --apply to edit")


if __name__ == "__main__":
    main()

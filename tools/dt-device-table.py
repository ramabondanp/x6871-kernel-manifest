#!/usr/bin/env python3
"""Susun tabel perangkat X6871: node DT -> compatible -> driver/modul.

Input (urutan argumen):
  devices.tsv      dari tools/dts-devices.py
  compat-map.tsv   dari tools/dt-compat-map.py  (alias of: di .ko)
  compat-src.txt   hasil grep literal compatible di source ("file:compatible")
  src-module.tsv   dari tools/src-to-module.py   (berkas.c -> nama modul)

Direktori .ko untuk menentukan "sudah kita build" vs "masih stock" diambil
dari konstanta SRC_DIRS / STOCK_DIRS di bawah (sesuaikan kalau path berubah).

Output: Markdown ke stdout, dikelompokkan per subsistem.
"""

import glob
import os
import re
import sys

L = os.environ.get("TMPDIR", "/serverhive1/ramabondanp/tmp")
KD = os.environ.get("KERNEL_VER", "6.12.38-android16-5-g2c4fd33ae6d8-4k")

SRC_DIRS = [
    f"{L}/twrp-src/lib/modules/{KD}",
    f"{L}/dlkm-src/vendor_dlkm/lib/modules/{KD}",
    f"{L}/dlkm-src/odm_dlkm/lib/modules/{KD}",
]

STOCK_DIRS = [
    f"{L}/twrp-set2/lib/modules/{KD}",
    f"{L}/stock-dlkm/vendor_dlkm/lib/modules",
    f"{L}/stock-dlkm/odm_dlkm/lib/modules",
]

GROUPS = [
    ("Storage / UFS / MMC", r"ufs|scsi|cqhci|msdc|mmc|sdhci"),
    ("USB / Type-C / Charging", r"usb|typec|tcpc|charger|chg|battery|gauge|extcon|mtu3|xhci|otg|rfc|pd-|ucsi|mux|switch|^tc,|/tc_|tran_ldo|hl7139|tfcp|pca_|ambient_detect|temp_forecast"),
    ("Display / Touch / LED", r"disp|drm|dsi|mipi_tx|panel|lcm|backlight|led|pwm|touch|gt9|hx83|ft3|ili|focal|pixelworks"),
    ("Kamera / Flash", r"cam|imgsensor|eeprom|vcm|af-|flash|imgsys|seninf|camsv|mraw|dip"),
    ("Audio", r"audio|sound|snd|codec|amp|accdet|headset|jack|dmic|i2s|fs15|aw87|aw88|spk|vow|adsp|fsm|tfa"),
    ("Connectivity (WiFi/BT/GPS/NFC/FM)", r"wifi|wlan|bluetooth|bt-|conn|gps|gnss|nfc|pn5|fm-|wmt|consys|epda|hbt|fmradio"),
    ("Sensor (IMU/ALSPS/MAG/BARO)", r"sensor|accel|gyro|alsps|mag-|baro|msensor|sc7|bmi|icm|ak0|akm|stk|tcs|epl|ltr|cm36|sensorhub"),
    ("Fingerprint / Secure / TrustZone", r"fp|fingerprint|tz|tee|tui|sec-|gz|trusty|keymaster|smmu|iommu|svp|mtee"),
    ("PMIC / Regulator / Thermal", r"pmic|regulator|mt63|mt66|thermal|cooling|auxadc|rt5|ldo|buck|vcore|fan"),
    ("Power / PM / Clock / Debug", r"power|pm-|cpufreq|clk|clock|debug|aee|sram|nvmem|efuse|rproc|scp|mcupm|sspm|mali|gpu"),
    ("Modem / Jaringan seluler", r"md|modem|ccci|mddp|dpmaif|ccif|smd|sim|rpc"),
]

BAD_MOD_NAMES = {"ddk_kconfigs", "ddk_makefile", "srcs", "hdrs"}


def read_tsv(path):
    with open(path, errors="replace") as fh:
        return [line.rstrip("\n").split("\t") for line in fh if line.strip()]


def norm_alias(comp):
    return comp[:-2] if comp.endswith("C*") else comp


def canon(comp):
    """Samakan bentuk DT <-> alias modul: spasi/'-' jadi '_' (aturan modalias)."""
    return re.sub(r"[\s\-/]", "_", comp.strip()).lower()


def load_map(path, dirs):
    """alias of: -> modul, hanya untuk direktori tertentu."""
    m = {}
    for parts in read_tsv(path):
        if len(parts) < 3:
            continue
        if not any(parts[2].startswith(d) for d in dirs):
            continue
        m.setdefault(canon(norm_alias(parts[0])), set()).add(parts[1])
    return m


def load_src(path):
    """compat-src.txt berisi "berkas:compatible" (grep -Ho)."""
    m = {}
    with open(path, errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            if "\t" in line:
                f, comp = line.split("\t", 1)
            elif ":" in line:
                f, comp = line.rsplit(":", 1)
            else:
                continue
            m.setdefault(canon(comp), set()).add(f)
    return m


def load_srcmod(path):
    m = {}
    for parts in read_tsv(path):
        if len(parts) >= 2:
            m.setdefault(os.path.basename(parts[0]), set()).add(parts[1])
    return m


def ko_names(dirs):
    s = set()
    for d in dirs:
        for p in glob.glob(os.path.join(d, "*.ko")):
            s.add(os.path.basename(p)[:-3])
    return s


def similar(compat, aliases):
    out = []
    for a in aliases:
        if a != compat and (compat.startswith(a) or a.startswith(compat)):
            if min(len(a), len(compat)) >= 10:
                out.append(a)
    return sorted(set(out))[:2]


def best_file(files, comps):
    """Pilih berkas yang paling mungkin pemilik of_match (heuristik nama)."""
    keys = set()
    for c in comps.split("|"):
        tail = c.split(",")[-1].strip().lower()
        for part in re.split(r"[-_ ,]", tail):
            if len(part) >= 3:
                keys.add(part)
    def score(f):
        base = os.path.basename(f).lower()
        return (-sum(k in base for k in keys), len(f))
    return sorted(files, key=score)[0]


def group_for(comp, path):
    hay = f"{comp} {path}".lower()
    for name, pattern in GROUPS:
        if re.search(pattern, hay):
            return name
    return "Lain-lain"


def short(path):
    for marker in ("kernel_device_modules-6.12/", "vendor/mediatek/kernel_modules/"):
        if marker in path:
            return path.split(marker, 1)[1]
    return path


def load_base_compat(path):
    """Kumpulan compatible yang sudah ada di base DTB (untuk kolom penanda)."""
    out = set()
    if not path or not os.path.exists(path):
        return out
    for parts in read_tsv(path):
        if len(parts) >= 2:
            for c in parts[1].split("|"):
                out.add(canon(c))
    return out


def main(dev_tsv, map_tsv, src_tsv, srcmod_tsv, dtsi_tsv=None, only=None):
    cmap_src = load_map(map_tsv, SRC_DIRS)
    cmap_stock = load_map(map_tsv, STOCK_DIRS)
    dmap = load_src(dtsi_tsv) if dtsi_tsv else {}
    base_compat = load_base_compat(os.environ.get("BASE_TSV", ""))
    smap = load_src(src_tsv)
    smod = load_srcmod(srcmod_tsv)
    have_src = ko_names(SRC_DIRS)
    have_stock = ko_names(STOCK_DIRS)

    rows, seen = [], set()
    for parts in read_tsv(dev_tsv):
        if len(parts) < 3:
            continue
        path, comps, status = parts[0], parts[1], parts[2]
        if status not in ("okay", "ok"):
            continue
        if (comps, path) in seen:
            continue
        seen.add((comps, path))

        kind, driver = "?", "—"
        cands = comps.split("|")

        def src_files(comp):
            allf = smap.get(canon(comp), set())
            return {f for f in allf if f.endswith(".c")} or allf

        def mods_of_files(files):
            mods = set()
            for f in files:
                mods |= smod.get(os.path.basename(f), set())
            return mods - BAD_MOD_NAMES

        if any(c in ("syscon", "simple-mfd", "simple-bus") for c in cands):
            rows.append((group_for(comps, path),
                         path.replace("/fragment@", "frag@").replace("/__overlay__", ""),
                         comps, "dt", "—"))
            continue

        # 1. alias of: di build kita = otoritatif (itu yang benar-benar bind)
        hits = set()
        for c in cands:
            hits |= cmap_src.get(canon(c), set())
        stock_hits = set()
        for c in cands:
            stock_hits |= cmap_stock.get(canon(c), set())

        if hits:
            kind, driver = "module", ", ".join(f"`{m}`" for m in sorted(hits))
        elif stock_hits:
            # stock punya of_match ini, build kita tidak -> tidak akan bind
            kind, driver = "MISMATCH", ", ".join(f"`{m}`" for m in sorted(stock_hits))
        else:
            files = set()
            for c in cands:
                files |= src_files(c)
            mods = mods_of_files(files)
            pick = sorted(mods & have_src)
            if pick:
                kind, driver = "module", ", ".join(f"`{m}`" for m in pick[:3])
            else:
                pick = sorted(mods & have_stock)
                if pick:
                    kind, driver = "stock", ", ".join(f"`{m}`" for m in pick[:3])
                elif files:
                    kind, driver = "builtin", f"`{short(best_file(sorted(files), comps))}`"
                elif any(canon(c) in dmap for c in cands):
                    kind = "dt"
                else:
                    cand = []
                    for c in cands:
                        cand += similar(c, cmap_src.keys() | cmap_stock.keys())
                    if cand:
                        kind = "MISMATCH"
                        driver = ", ".join(f"of_match `{c}`" for c in cand)

        rows.append((group_for(comps, path),
                     path.replace("/fragment@", "frag@").replace("/__overlay__", ""),
                     comps, kind, driver))

    if only:
        rows = [r for r in rows if only.lower() in (r[0] + r[1] + r[2]).lower()]

    order = {name: i for i, (name, _) in enumerate(GROUPS)}
    order["Lain-lain"] = 99
    rows.sort(key=lambda r: (order.get(r[0], 98), r[1]))

    stat = {}
    for r in rows:
        stat[r[3]] = stat.get(r[3], 0) + 1
    print(f"Total node device (status okay): {len(rows)}")
    print(", ".join(f"{k}={v}" for k, v in sorted(stat.items(), key=lambda x: -x[1])))
    print()

    cur = None
    label = {"module": "source", "stock": "**stock**", "builtin": "built-in",
             "dt": "node platform", "MISMATCH": "**MISMATCH**", "?": "tidak ada"}
    for grp, path, comps, kind, driver in rows:
        if grp != cur:
            cur = grp
            print(f"\n### {grp}\n")
            if base_compat:
                print("| Node | compatible | Driver | Asal | juga di base |")
                print("|---|---|---|---|---|")
            else:
                print("| Node | compatible | Driver | Asal |")
                print("|---|---|---|---|")
        if base_compat:
            juga = "ya" if any(canon(c) in base_compat for c in comps.split("|")) else "**tidak**"
            print(f"| `{path}` | `{comps}` | {driver} | {label[kind]} | {juga} |")
        else:
            print(f"| `{path}` | `{comps}` | {driver} | {label[kind]} |")


if __name__ == "__main__":
    if len(sys.argv) < 5:
        sys.exit(
            "Pakai: ./tools/dt-device-table.py <devices.tsv> <compat-map.tsv> "
            "<compat-src.txt> <src-module.tsv> [dtsi-compat.txt] [filter]"
        )
    dtsi_tsv = sys.argv[5] if len(sys.argv) > 5 else None
    only = sys.argv[6] if len(sys.argv) > 6 else None
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], dtsi_tsv, only)

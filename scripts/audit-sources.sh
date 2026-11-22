#!/bin/bash
# Cocokkan modul firmware -> file source, tanpa peduli nama file.
#
#   ./audit-sources.sh /path/ke/transsion-6.1 /path/ke/firmware-modules
#
# Kenapa alat ini ada
# -------------------
# Kasus `tran_ldo` membuktikan nama modul dan nama file source TIDAK harus sama:
#
#     firmware : tran_ldo.ko        (compatible "tran,tran_ldo")
#     source   : drivers/regulator/et5904.c
#
# Kalau kita mencari berdasarkan nama modul, modul itu terlihat "tidak ada
# source" dan kita akan menghabiskan waktu melakukan RE. Yang benar: ambil
# sidik jari dari `.ko` (simbol fungsi yang didefinisikan/diimpor, deskripsi,
# author), lalu cari file source mana pun yang mendefinisikan simbol-simbol itu.
#
# Alat ini melakukan itu untuk semua modul sekaligus:
#   - baca simbol FUNC tiap `.ko`
#   - indeks definisi fungsi di semua `.c/.h`
#   - untuk tiap modul, hitung file sumber mana yang mencakup simbol terbanyak
#   - laporkan persentase + klasifikasi
#
# Keluaran: tabel `modul -> file sumber terbaik (skor%)` yang langsung bisa
# dipakai untuk memutuskan port atau RE.
set -euo pipefail

SRC=${1:?pakai: ./audit-sources.sh <tree-source> <dir-modul-firmware> [modul...]}
KO=${2:?pakai: ./audit-sources.sh <tree-source> <dir-modul-firmware> [modul...]}
shift 2 || true

[ -d "$SRC" ] || { echo "ERROR: tree source $SRC tidak ada"; exit 1; }
[ -d "$KO" ]  || { echo "ERROR: dir modul $KO tidak ada"; exit 1; }

python3 - "$SRC" "$KO" "$@" <<'PY'
import os, re, subprocess, sys

src_root, ko_dir = sys.argv[1], sys.argv[2]
want = sys.argv[3:]

NOISE = {'__this_module', '__start_alloc_tags', '__stop_alloc_tags',
         '__llvm_fs_discriminator__', 'init_module', 'cleanup_module'}

def funcs(ko):
    o = subprocess.run(['readelf', '-sW', ko], capture_output=True, text=True).stdout
    defs, und = set(), set()
    for line in o.splitlines():
        p = line.split()
        if len(p) < 8:
            continue
        name = p[7]
        if name in NOISE:
            continue
        if p[6] == 'UND':
            und.add(name)
        elif p[4] in ('GLOBAL', 'WEAK') or p[3] == 'FUNC':
            defs.add(name)
    return defs, und

# --- indeks: nama fungsi -> file yang mendefinisikannya ---------------------
DEF = re.compile(r'^[A-Za-z_][\w \t\*]*?\b([A-Za-z_]\w*)\s*\(', re.M)
index = {}
files = 0
for dp, dn, fn in os.walk(src_root):
    dn[:] = [d for d in dn if d not in ('.git', 'out_bazel', 'bazel-out', 'bazel-bin')]
    for f in fn:
        if not f.endswith(('.c', '.h')):
            continue
        path = os.path.join(dp, f)
        try:
            text = open(path, errors='ignore').read()
        except OSError:
            continue
        files += 1
        for m in DEF.finditer(text):
            n = m.group(1)
            if len(n) >= 4:
                index.setdefault(n, set()).add(path)

print(f"tree source : {src_root}  ({files} file .c/.h)", file=sys.stderr)
print(f"modul       : {ko_dir}", file=sys.stderr)

mods = want or sorted(f[:-3] for f in os.listdir(ko_dir) if f.endswith('.ko'))
ada, kosong, takada = [], [], []

for mod in mods:
    ko = os.path.join(ko_dir, mod + '.ko')
    if not os.path.exists(ko):
        kosong.append(mod)
        continue
    defs, und = funcs(ko)
    if not defs:
        kosong.append(mod)
        continue
    score = {}
    for sym in defs:
        for f in index.get(sym, ()):
            score[f] = score.get(f, 0) + 1
    if not score:
        takada.append((mod, len(defs)))
        continue
    ranked = sorted(score.items(), key=lambda kv: -kv[1])
    best, hit = ranked[0]
    ada.append((mod, len(defs), hit, 100.0 * hit / len(defs), best, ranked[1:3]))

print()
for mod, total, hit, pct, best, rest in sorted(ada, key=lambda x: -x[3]):
    print(f"{pct:5.1f}%  {hit:4d}/{total:<4d} {mod:46s} {best}")
    for f, c in rest:
        if c >= 3:
            print(f"{'':21s} {c:4d}/{total:<4d} {'':46s} {f}")

print()
if takada:
    print(f"TIDAK ADA SOURCE ({len(takada)}):")
    print("  " + ", ".join(m for m, _ in takada))
    print()
if kosong:
    print(f"KO TIDAK ADA ({len(kosong)}):")
    print("  " + ", ".join(kosong))
    print()
print(f"ringkas: {len(ada)} ada source, {len(takada)} tidak ada, {len(kosong)} tanpa .ko")
PY

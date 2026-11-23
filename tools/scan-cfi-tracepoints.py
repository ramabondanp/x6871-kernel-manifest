#!/usr/bin/env python3
# Static KCFI tracepoint-callback scanner for X6871 modules.
#
# KCFI stores a 32-bit type hash in the four bytes before every function
# entry, and every indirect call site compares it with the type hash of the
# function-pointer prototype.  Tracepoint probes are registered through
# tracepoint_probe_register(tp, void *func, data), so a wrong probe prototype
# (for example int instead of enum ufs_trace_str_t) is only caught at runtime
# by the CFI check.
#
# This tool extracts:
#   - the expected hash from each __traceiter_<name> call site in vmlinux and
#     in the modules (for tracepoints defined out of tree),
#   - the actual hashes of the functions stored next to a tracepoint name (or
#     __tracepoint_<name>) pointer in each module,
#   - the hashes of functions passed directly to tracepoint_probe_register().
# and reports mismatches before flashing the images.
#
# Usage:
#   tools/scan-cfi-tracepoints.py \
#     --vmlinux <bazel-bin>/kernel_device_modules-6.18/mgk_64_k618_kernel_aarch64.user/vmlinux \
#     --modules <staging>/lib/modules/<kver> [--modules ...] [--verbose]
#
# A module that uses a private registration wrapper (for example
# ufs-mediatek-mod) may be reported as UNSCANNED; its callbacks must be
# compared by hand.  The scanner exits non-zero when it finds a mismatch.

import argparse
import os
import struct
import sys

SHT_SYMTAB = 2
SHT_RELA = 4
SHT_NOBITS = 8
STT_FUNC = 2
STT_SECTION = 3
SHF_WRITE = 0x1
SHF_ALLOC = 0x2
SHF_EXECINSTR = 0x4
# Tables that store tracepoint names without being probe registrations.
SECTION_BLOCKLIST = (
    "__tracepoints",
    "__ksymtab",
    "__kcrctab",
    "__kflagstab",
    "__bug_table",
    "__jump_table",
    "__mcount_loc",
    "__dyndbg",
    "__param",
    "__versions",
    ".altinstructions",
    ".modinfo",
    ".codetag",
    ".gnu.linkonce.this_module",
    ".BTF",
    ".static_call_sites",
)
EM_AARCH64 = 183
BRK_KCFI = 0xD4304500
KCFI_BRK_MASK = 0xFFE0001F
KCFI_BRK_BASE = 0xD4200000


class ElfError(Exception):
    pass


class Section:
    __slots__ = ("name_idx", "name", "type", "flags", "addr", "offset",
                 "size", "link", "info", "entsize", "data")

    def __init__(self):
        self.data = None


class Symbol:
    __slots__ = ("name", "info", "shndx", "value", "size")

    def __init__(self, name, info, shndx, value, size):
        self.name = name
        self.info = info
        self.shndx = shndx
        self.value = value
        self.size = size


class Elf:
    def __init__(self, path):
        self.path = path
        with open(path, "rb") as f:
            self.buf = f.read()
        if self.buf[:4] != b"\x7fELF":
            raise ElfError("not an ELF file")
        ei_class = self.buf[4]
        ei_data = self.buf[5]
        if ei_class != 2 or ei_data != 1:
            raise ElfError("only ELF64 little-endian is supported")
        (self.e_shoff,) = struct.unpack_from("<Q", self.buf, 0x28)
        (self.e_shentsize, self.e_shnum, self.e_shstrndx) = struct.unpack_from(
            "<HHH", self.buf, 0x3A)
        self.sections = []
        self._parse_sections()
        self._parse_symbols()

    def _parse_sections(self):
        for i in range(self.e_shnum):
            off = self.e_shoff + i * self.e_shentsize
            vals = struct.unpack_from("<IIQQQQIIQQ", self.buf, off)
            sec = Section()
            (sec.name_idx, sec.type, sec.flags, sec.addr, sec.offset, sec.size,
             sec.link, sec.info, _addralign, sec.entsize) = vals
            self.sections.append(sec)
        shstr = self.sections[self.e_shstrndx]
        base = shstr.offset
        for sec in self.sections:
            start = base + sec.name_idx
            end = self.buf.index(b"\0", start)
            sec.name = self.buf[start:end].decode("utf-8", "replace")

    def _parse_symbols(self):
        self.symbols = []
        for sec in self.sections:
            if sec.type != SHT_SYMTAB:
                continue
            strtab = self.sections[sec.link]
            entsize = sec.entsize or 24
            count = sec.size // entsize
            for i in range(count):
                off = sec.offset + i * entsize
                (name_idx, info, _other, shndx, value,
                 size) = struct.unpack_from("<IBBHQQ", self.buf, off)
                start = strtab.offset + name_idx
                end = self.buf.index(b"\0", start)
                name = self.buf[start:end].decode("utf-8", "replace")
                self.symbols.append(Symbol(name, info, shndx, value, size))

    def section_data(self, sec):
        if sec.type == SHT_NOBITS:
            return b""
        return self.buf[sec.offset:sec.offset + sec.size]

    def section_bytes_at(self, sec, off, length):
        if off < 0 or off + length > sec.size:
            return None
        return self.buf[sec.offset + off:sec.offset + off + length]


def kcfi_hash_from_traceiter(elf, sym):
    """Extract the KCFI type hash from a __traceiter_* function body."""
    if sym.shndx <= 0 or sym.shndx >= len(elf.sections):
        return None
    sec = elf.sections[sym.shndx]
    if not (sec.flags & SHF_EXECINSTR):
        return None
    size = sym.size or 256
    data = elf.section_bytes_at(sec, sym.value - sec.addr, size)
    if not data:
        return None
    insns = struct.unpack_from("<%dI" % (len(data) // 4), data, 0)
    # Find the KCFI brk and the movk/movz pair that builds the expected hash.
    for i, insn in enumerate(insns):
        if (insn & KCFI_BRK_MASK) != KCFI_BRK_BASE:
            continue
        if insn != BRK_KCFI:
            continue
        pairs = {}
        for j in range(max(0, i - 10), i):
            cur = insns[j]
            # movk wN, #imm, lsl #0 / #16
            if (cur & 0xFFE0001F) in (0x72800011, 0x72A00011):
                reg = cur & 0x1F
                hw = (cur >> 21) & 1
                imm = (cur >> 5) & 0xFFFF
                pairs.setdefault(reg, {})[hw] = imm
            # movz wN, #imm, lsl #0 / #16
            elif (cur & 0xFFE0001F) in (0x52800011, 0x52A00011):
                reg = cur & 0x1F
                hw = (cur >> 21) & 1
                imm = (cur >> 5) & 0xFFFF
                pairs.setdefault(reg, {})[hw] = imm
        for reg, parts in pairs.items():
            if 0 in parts and 1 in parts:
                return (parts[1] << 16) | parts[0]
    return None


def build_expected_hashes(elf, table):
    for sym in elf.symbols:
        if sym.name.startswith("__traceiter_") and sym.shndx:
            name = sym.name[len("__traceiter_"):]
            h = kcfi_hash_from_traceiter(elf, sym)
            if h is not None:
                table.setdefault(name, h)


def build_func_hashes(elf):
    hashes = {}
    for sym in elf.symbols:
        if (sym.info & 0xF) != STT_FUNC or not sym.shndx:
            continue
        if sym.shndx >= len(elf.sections):
            continue
        sec = elf.sections[sym.shndx]
        if not (sec.flags & SHF_EXECINSTR) or sym.value - sec.addr < 4:
            continue
        raw = elf.section_bytes_at(sec, sym.value - sec.addr - 4, 4)
        if raw is None:
            continue
        hashes[(sym.shndx, sym.value)] = (struct.unpack("<I", raw)[0], sym.name)
    return hashes


def reloc_sections(elf):
    out = {}
    for sec in elf.sections:
        if sec.type != SHT_RELA:
            continue
        target = sec.info
        if target >= len(elf.sections):
            continue
        relocs = {}
        entsize = sec.entsize or 24
        for i in range(sec.size // entsize):
            off = sec.offset + i * entsize
            r_offset, r_info, r_addend = struct.unpack_from(
                "<QQq", elf.buf, off)
            sym_idx = r_info >> 32
            r_type = r_info & 0xFFFFFFFF
            relocs[r_offset] = (sym_idx, r_type, r_addend)
        out.setdefault(target, {}).update(relocs)
    return out


def resolve_reloc(elf, relocs, offset):
    item = relocs.get(offset)
    if not item:
        return None
    sym_idx, _r_type, addend = item
    if sym_idx >= len(elf.symbols):
        return None
    sym = elf.symbols[sym_idx]
    if sym.shndx == 0:
        # Undefined symbol (for example __tracepoint_foo): return its name.
        return ("undef", sym.name, None)
    if sym.shndx >= len(elf.sections):
        return None
    sec = elf.sections[sym.shndx]
    value = sym.value - sec.addr + addend
    if (sym.info & 0xF) == STT_SECTION:
        value = addend
    return ("defined", sec, value)


def read_c_string(elf, sec, off):
    if off < 0 or off >= sec.size:
        return None
    end = elf.buf.find(b"\0", sec.offset + off, sec.offset + sec.size)
    if end < 0:
        return None
    return elf.buf[sec.offset + off:end].decode("utf-8", "replace")


def scan_module(path, expected, func_hashes, verbose=False):
    elf = Elf(path)
    relocs_by_sec = reloc_sections(elf)
    findings = []
    name_hits = 0
    unpaired = 0
    unpaired_list = []
    for target_idx, relocs in relocs_by_sec.items():
        target = elf.sections[target_idx]
        if not (target.flags & SHF_ALLOC) or (target.flags & SHF_EXECINSTR):
            continue
        if not (target.flags & SHF_WRITE):
            continue
        if target.name.startswith(SECTION_BLOCKLIST):
            continue
        for offset in sorted(relocs):
            resolved = resolve_reloc(elf, relocs, offset)
            if not resolved:
                continue
            kind, obj, value = resolved
            tp_name = None
            if kind == "undef" and obj.startswith("__tracepoint_"):
                tp_name = obj[len("__tracepoint_"):]
            elif kind == "defined":
                sec, off = obj, value
                if sec.flags & SHF_ALLOC and not (sec.flags & SHF_EXECINSTR):
                    text = read_c_string(elf, sec, off)
                    if text in expected:
                        tp_name = text
            if not tp_name or tp_name not in expected:
                continue
            name_hits += 1
            # Registration entries store the name first and the probe function
            # in the next pointer slot.  Both fields are ordinary ABS64
            # relocations to a string and to a function entry.
            cand_off = offset + 8
            cand = resolve_reloc(elf, relocs, cand_off)
            if not cand:
                unpaired += 1
                unpaired_list.append((tp_name, target.name, offset))
                continue
            kind2, sec2, value2 = cand
            if kind2 != "defined" or not (sec2.flags & SHF_EXECINSTR):
                unpaired += 1
                unpaired_list.append((tp_name, target.name, offset))
                continue
            hit = func_hashes.get((elf.sections.index(sec2), value2))
            if hit is None:
                unpaired += 1
                unpaired_list.append((tp_name, target.name, offset))
                continue
            actual, fn_name = hit
            exp = expected[tp_name]
            findings.append((tp_name, fn_name, exp, actual,
                             offset, cand_off, target.name))
    return findings, name_hits, unpaired, unpaired_list


R_AARCH64_ADR_PREL_PG_HI21 = 275
R_AARCH64_ADD_ABS_LO12_NC = 277
R_AARCH64_CALL26 = 283


def scan_register_calls(elf, expected, func_hashes):
    """Find tracepoint_probe_register(tp, func, data) call sites in .text."""
    relocs_by_sec = reloc_sections(elf)
    findings = []
    hits = 0
    for target_idx, relocs in relocs_by_sec.items():
        sec = elf.sections[target_idx]
        if not (sec.flags & SHF_EXECINSTR):
            continue
        for call_off, (sym_idx, r_type, _addend) in sorted(relocs.items()):
            if r_type != R_AARCH64_CALL26:
                continue
            if sym_idx >= len(elf.symbols):
                continue
            call_sym = elf.symbols[sym_idx]
            if call_sym.name != "tracepoint_probe_register":
                continue
            tp_name = None
            tp_off = -1
            fn_entry = None
            fn_off = -1
            for off in sorted(o for o in relocs if call_off - 0x80 <= o < call_off):
                si, ty, addend = relocs[off]
                if ty != R_AARCH64_ADR_PREL_PG_HI21:
                    continue
                if si >= len(elf.symbols):
                    continue
                sym = elf.symbols[si]
                # The matching :lo12: add must follow the adrp.
                add = relocs.get(off + 4)
                if not add or add[0] != si or add[1] != R_AARCH64_ADD_ABS_LO12_NC:
                    continue
                if sym.name.startswith("__tracepoint_"):
                    tp_name = sym.name[len("__tracepoint_"):]
                    tp_off = off
                if sym.shndx == 0:
                    continue
                tsec = elf.sections[sym.shndx]
                if not (tsec.flags & SHF_EXECINSTR):
                    continue
                value = sym.value - tsec.addr + addend
                if (sym.info & 0xF) == STT_SECTION:
                    value = addend
                if (sym.shndx, value) in func_hashes:
                    fn_entry = (sym.shndx, value)
                    fn_off = off
            if tp_name is None or fn_entry is None:
                continue
            if tp_name not in expected:
                continue
            if tp_off > fn_off + 8:
                continue
            hits += 1
            actual, fn_name = func_hashes[fn_entry]
            exp = expected[tp_name]
            findings.append((tp_name, fn_name, exp, actual, call_off, None,
                             sec.name))
    return findings, hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vmlinux", required=True)
    ap.add_argument("--modules", action="append", default=[],
                    help="module directory (repeatable)")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    expected = {}
    print("scanning vmlinux for traceiter hashes ...", flush=True)
    vmlinux = Elf(args.vmlinux)
    build_expected_hashes(vmlinux, expected)
    print("vmlinux tracepoints: %d" % len(expected))

    module_paths = []
    for d in args.modules:
        for root, _dirs, files in os.walk(d):
            for f in sorted(files):
                if f.endswith(".ko"):
                    module_paths.append(os.path.join(root, f))
    print("modules: %d" % len(module_paths))

    # Second pass: modules can define their own tracepoints.
    elfs = {}
    for path in module_paths:
        try:
            elf = Elf(path)
        except (ElfError, OSError) as exc:
            print("SKIP %s: %s" % (path, exc), file=sys.stderr)
            continue
        elfs[path] = elf
        build_expected_hashes(elf, expected)
    print("total tracepoints (vmlinux + modules): %d" % len(expected))

    total_hits = 0
    total_unpaired = 0
    mismatches = 0
    unscanned = []
    for path, elf in sorted(elfs.items()):
        func_hashes = build_func_hashes(elf)
        findings, hits, unpaired, unpaired_list = scan_module(
            path, expected, func_hashes)
        call_findings, call_hits = scan_register_calls(
            elf, expected, func_hashes)
        findings += call_findings
        hits += call_hits
        has_reg = any(s.name == "tracepoint_probe_register" and s.shndx == 0
                      for s in elf.symbols)
        if has_reg and not hits:
            unscanned.append(os.path.basename(path))
        if not findings and not hits:
            continue
        total_hits += hits
        total_unpaired += unpaired
        if args.verbose:
            for (tp, secname, off) in unpaired_list:
                print("UNPAIRED %s: %s (%s+0x%x)"
                      % (os.path.basename(path), tp, secname, off))
        for (tp, fn, exp, act, off, foff, secname) in findings:
            status = "OK" if exp == act else "MISMATCH"
            if exp != act:
                mismatches += 1
            if status == "MISMATCH" or args.verbose:
                print("%-8s %s: %s -> %s (expected %08x actual %08x, %s+0x%x)"
                      % (status, os.path.basename(path), tp, fn, exp, act,
                         secname, off))
    for name in unscanned:
        print("UNSCANNED %s: uses tracepoint_probe_register but no probe "
              "pointer was paired" % name)
    print("pairs checked: %d, unpaired names: %d, mismatches: %d"
          % (total_hits, total_unpaired, mismatches))
    if total_hits == 0:
        print("WARNING: no tracepoint callback pairs found", file=sys.stderr)
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())

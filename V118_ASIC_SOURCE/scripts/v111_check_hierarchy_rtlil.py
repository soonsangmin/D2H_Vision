#!/usr/bin/env python3
"""Read unlowered Yosys RTLIL; count SRAM instances reachable from the real AI top.

Does NOT require `proc`, `memory_map`, optimization, or JSON. RTLIL is a
hierarchical representation that supports unlowered processes.
"""
from collections import Counter
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
path = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "output/v111_ai_top_hierarchy/ai_top_hierarchy.il"
if not path.is_file():
    raise SystemExit(f"[FAIL] Missing Yosys RTLIL: {path}")

modules = {}
module = None
cell_count = 0
with path.open(encoding="utf-8", errors="replace") as f:
    for line in f:
        # Distinguish a top-level `module` from a `process` or a `cell`.
        if line.startswith("module "):
            name = line.split(None, 1)[1].strip().lstrip("\\")
            if not name or name in modules:
                raise SystemExit(f"[FAIL] Duplicate/invalid RTLIL module: {name}")
            modules[name] = []
            module = name
        elif line.startswith("  cell ") and module is not None:
            # RTLIL: cell <type> <instance-name> [parameters, connections] end
            parts = line.strip().split(None, 2)
            if len(parts) != 3:
                raise SystemExit(f"[FAIL] Unexpected RTLIL cell declaration: {line.rstrip()}")
            _, cell_type, instance = parts
            modules[module].append((cell_type.lstrip("\\"), instance.lstrip("\\")))
            cell_count += 1
        elif line.startswith("end") and module is not None:
            module = None

TOP = "asic_ai_onchip_top"
if TOP not in modules:
    raise SystemExit(f"[FAIL] AI top {TOP} not found among {len(modules)} RTLIL modules")
MACRO_2K = "sky130_sram_2kbyte_1rw1r_32x512_8"
MACRO_1K = "sky130_sram_1kbyte_1rw1r_32x256_8"
counts = Counter()
banks = Counter()
missing = Counter()
visited_types = set()

# Walk module types with multiplicity. No pruning/constant propagation is done.
def visit(type_name, prefix, ancestors):
    if type_name not in modules:
        missing[type_name] += 1
        return
    if type_name in ancestors:
        raise SystemExit(f"[FAIL] Recursive module hierarchy: {type_name}")
    visited_types.add(type_name)
    parents = ancestors | {type_name}
    for cell_type, instance in modules[type_name]:
        hierarchy = prefix + "/" + instance
        if cell_type == MACRO_2K:
            counts["2k"] += 1
            for b in range(8):
                if f"u_bank{b}" in hierarchy:
                    banks[b] += 1
                    break
            else:
                banks["unclassified"] += 1
        elif cell_type == MACRO_1K:
            counts["1k"] += 1
        elif cell_type in modules:
            visit(cell_type, hierarchy, parents)
        elif not cell_type.startswith("$"):
            missing[cell_type] += 1

visit(TOP, TOP, set())
expected = [480, 240, 180, 20, 6, 2, 180, 20]
print(f"V111_TOP={TOP}")
print(f"V111_RTLIL_MODULE_TYPES={len(modules)}")
print(f"V111_RTLIL_CELL_DECLARATIONS={cell_count}")
print(f"V111_REACHABLE_MODULE_TYPES={len(visited_types)}")
print(f"V111_2K_SRAM_COUNT={counts['2k']}")
print(f"V111_1K_CNN_SRAM_COUNT={counts['1k']}")
print("V111_HANDSEG_BANK_COUNTS=" + " ".join(str(banks[b]) for b in range(8)))
print(f"V111_UNCLASSIFIED_2K={banks['unclassified']}")
if counts["2k"] != 1128:
    print("[DIAG] Non-internal module types not resolved in RTLIL:")
    for typ, qty in missing.most_common(12):
        print(f"    {qty}: {typ}")
    raise SystemExit("[FAIL] Expected 1128 reachable 2KiB SRAM macros from REAL AI top")
if banks["unclassified"] or any(banks[b] != expected[b] for b in range(8)):
    print("[WARN] SRAM total matched, but bank path classification differs; inspect names")
print("[PASS] 1128 HandSeg physical SRAM instance declarations reachable from REAL AI top")
print("[LIMIT] Hierarchy elaboration ONLY. Not functionality, full-chip OpenDB, GDS, STA, DRC or LVS")

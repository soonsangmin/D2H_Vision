#!/usr/bin/env python3
"""Count hard SRAM only when reachable from asic_ai_onchip_top in Yosys JSON."""
from collections import Counter
from pathlib import Path
import json
import sys

root = Path(__file__).resolve().parent.parent
path = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'output/v111_ai_top_hierarchy/ai_top_hierarchy.json'
if not path.is_file():
    raise SystemExit(f'[FAIL] Missing elaborated Yosys JSON: {path}')
with path.open() as f:
    design = json.load(f)
mods = design['modules']
top_candidates = [m for m in mods if m.lstrip('\\') == 'asic_ai_onchip_top']
if len(top_candidates) != 1:
    raise SystemExit(f'[FAIL] Need one asic_ai_onchip_top; found {top_candidates}')
top = top_candidates[0]
macro_2k = 'sky130_sram_2kbyte_1rw1r_32x512_8'
macro_1k = 'sky130_sram_1kbyte_1rw1r_32x256_8'
counts = Counter()
banks = Counter()
other = Counter()

# Do NOT count unused standalone wrapper definitions. Walk the hierarchy from
# the actual AI top, retaining multiplicity of submodule instances.
def visit(module, hierarchy, active):
    if module in active:
        raise RuntimeError(f'[FAIL] Recursive module hierarchy at {module}')
    if module not in mods:
        return
    next_active = active | {module}
    for name, cell in mods[module].get('cells', {}).items():
        typ = cell['type'].lstrip('\\')
        fullpath = hierarchy + '/' + name.lstrip('\\')
        if typ == macro_2k:
            counts['HandSeg 2KiB'] += 1
            for b in range(8):
                if f'u_bank{b}' in fullpath:
                    banks[b] += 1
                    break
            else:
                banks['unclassified'] += 1
        elif typ == macro_1k:
            counts['CNN 1KiB'] += 1
        elif typ in mods:
            visit(typ, fullpath, next_active)
        elif typ.startswith('$mem'):
            other['inferred-memory-cells'] += 1
        elif typ.startswith('$'):
            other['yosys-internal-cells'] += 1

visit(top, top, set())
expected = [480, 240, 180, 20, 6, 2, 180, 20]
print('V111_TOP=' + top)
print('V111_2K_SRAM_COUNT=' + str(counts['HandSeg 2KiB']))
print('V111_1K_CNN_SRAM_COUNT=' + str(counts['CNN 1KiB']))
print('V111_HANDSEG_BANK_COUNTS=' + ' '.join(str(banks[b]) for b in range(8)))
print('V111_UNCLASSIFIED_2K=' + str(banks['unclassified']))
print('V111_INFERRED_MEM_CELLS=' + str(other['inferred-memory-cells']))
if counts['HandSeg 2KiB'] != 1128:
    raise SystemExit('[FAIL] Expected 1128 real 2KiB SRAM instances REACHABLE from AI TOP')
if banks['unclassified']:
    print('[WARN] Found reachable SRAM instances whose bank could not be classified')
if any(banks[b] != expected[b] for b in range(8)):
    print('[WARN] Bank grouping differs from original V1.10 names; check hierarchy paths')
print('[PASS] 1128 HandSeg physical SRAM instances reachable from REAL AI top')
print('[LIMIT] Elaboration only; not memory-mapped CNN/weight ROM, not functional equivalence, not OpenDB, not PnR/GDS')

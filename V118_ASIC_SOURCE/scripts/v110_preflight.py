#!/usr/bin/env python3
"""Read-only source audit. This is NOT equivalence, DRC, or synthesis."""
from pathlib import Path
import csv, math, re, sys
root = Path(__file__).resolve().parent.parent
must = [
    'rtl/memory/reference_feature_memory.sv',
    'rtl/memory/v109_handseg_feature_memory_macro.sv',
    'rtl/memory/v109_handseg_feature_sram_bank.sv',
    'rtl/memory/sky130_sram_2kbyte_1rw1r_32x512_8_blackbox.v',
    'docs/V106_HANDSEG_BANK_CAPACITY.csv',
    'macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.lef',
]
for name in must:
    p = root / name
    if not p.is_file() or p.stat().st_size == 0:
        sys.exit(f'[BLOCKED] Missing {name}')
ref = (root / must[0]).read_text()
wrap = (root / must[1]).read_text()
bank = (root / must[2]).read_text()
top = (root / 'asic/v110_handseg_8bank_sram_probe.sv').read_text()
config = (root / 'config/config_v110_handseg_8bank_sram_probe.mk').read_text()
assert 'reference_feature_memory #(.BANK0_INIT_FILE(""))' in top
assert 'localparam integer HARD_FEATURE_ENABLED = (BANK0_INIT_FILE == "")' in ref
assert '`ifdef V109_SINGLE_COPY_SRAM' in ref
assert 'v109_handseg_feature_memory_macro #(' in ref
assert 'v107_handseg_feature_memory_macro #(' in ref
assert wrap.count('v109_handseg_feature_sram_bank #(.WORDS(') == 8
assert bank.count('sky130_sram_2kbyte_1rw1r_32x512_8 u_') == 2
assert 'SYNTH_MOCK_LARGE_MEMORIES = 0' in config
assert '-D V107_HARD_FEATURE_SRAM -D V109_SINGLE_COPY_SRAM' in config
rows = list(csv.DictReader((root/'docs/V106_HANDSEG_BANK_CAPACITY.csv').open()))
assert len(rows) == 8
expected = [480,240,180,20,6,2,180,20]
actual = []
for n,row in enumerate(rows):
    words = int(row['allocated_words'])
    actual.append(math.ceil(words/512)*2)
    print(f'[BANK {n}] {words:>7} x 64-bit words, {actual[-1]:>4} physical 2KiB macros')
assert actual == expected, (actual,expected)
assert sum(actual) == 1128
lef = (root / must[-1]).read_text()
m = re.search(r'\bSIZE\s+([0-9.]+)\s+BY\s+([0-9.]+)\s*;', lef)
assert m, 'LEF size missing'
area = 1128 * float(m.group(1)) * float(m.group(2)) / 1e6
print(f'[PASS] HandSeg 8 banks: {sum(actual)} SRAM macros; macro area ~{area:.2f} mm^2')
print('[LIMIT] This test checks sources and capacity ONLY. No Yosys/OpenDB verified yet.')

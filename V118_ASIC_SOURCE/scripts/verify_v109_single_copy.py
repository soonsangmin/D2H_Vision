#!/usr/bin/env python3
"""V109 source/config integrity and macro budgeting, NOT a simulation or LVS signoff."""
from pathlib import Path
import re,csv
root=Path(__file__).resolve().parents[1]
ref=(root/'rtl/memory/reference_feature_memory.sv').read_text()
w=(root/'rtl/memory/v109_handseg_feature_memory_macro.sv').read_text()
b=(root/'rtl/memory/v109_handseg_feature_sram_bank.sv').read_text()
assert '`ifdef V109_SINGLE_COPY_SRAM' in ref
assert 'v109_handseg_feature_memory_macro #(' in ref
assert 'v107_handseg_feature_memory_macro #(' in ref, 'Legacy V107 path must remain'
assert 'rd0_rw_port_busy' in w and 'wr_addr_i[16:9] == rd0_req_addr_i[16:9]' in w
assert w.count('v109_handseg_feature_sram_bank #(.WORDS(')==8
assert b.count('sky130_sram_2kbyte_1rw1r_32x512_8 u_')==2
assert '.dout0(d0_lo)' in b and '.dout1(d1_hi)' in b
assert '.web0(~wr_active)' in b
rows=list(csv.DictReader((root/'docs/V106_HANDSEG_BANK_CAPACITY.csv').open()))
assert len(rows)==8
blocks=sum((int(row['allocated_words'])+511)//512 for row in rows)
macros=blocks*2
assert blocks==564,(blocks,macros)
assert macros==1128
old_macros=blocks*4
area=683.1*416.54/1_000_000
print(f'[PASS] Source routing: 2 SRAM per 64-bit x 512 tile, with V107 kept intact')
print(f'[BANKS] {len(rows)} banks, {blocks} tiles')
print(f'[V107] {old_macros} macros, {old_macros*area:.2f} mm^2 macro-only')
print(f'[V109] {macros} macros, {macros*area:.2f} mm^2 macro-only')
print('[GATE] FPGA/AI end-to-end equivalence, full-chip physical fit, DRC, LVS and STA still unverified')

#!/usr/bin/env python3
"""Static checks for V1.07 macro banking. Not a substitute for HDL/STA."""
from pathlib import Path
import re,csv
r=Path(__file__).resolve().parents[1]
m=(r/'rtl/memory/reference_feature_memory.sv').read_text()
h=(r/'rtl/memory/v107_handseg_feature_memory_macro.sv').read_text()
b=(r/'rtl/memory/v107_handseg_feature_sram_bank.sv').read_text()
c=(r/'config/config_onchip_v107_hard_feature.mk').read_text()
assert 'V107_HARD_FEATURE_SRAM' in m and 'BANK0_INIT_FILE == ""' in m
assert 'g_v106_reference' in m and 'g_v107_physical' in m
assert h.count('v107_handseg_feature_sram_bank #(.WORDS(')==8
assert b.count('sky130_sram_2kbyte_1rw1r_32x512_8 u_')==4
assert 'collide0' in h and 'collide1' in h and 'wr_ready_o' in h
assert '-D V107_HARD_FEATURE_SRAM' in c
assert 'SYNTH_MOCK_LARGE_MEMORIES = 0' in c
rows=list(csv.DictReader((r/'docs/V106_HANDSEG_BANK_CAPACITY.csv').open()))
assert len(rows)==8
count=0
for x in rows:
    words=int(x['allocated_words']); blocks=(words+511)//512; n=4*blocks
    count+=n
    print(f"[BANK] {x['bank_name']:12s} words={words:6d} blocks={blocks:3d} mirrored_2KiB_macros={n:4d}")
assert count==2256,count
macro_area_mm2=(683.1*416.54)/1e6
print('[OK] Bank geometry: 2256 physical SRAM macros (2KiB each), two synchronized copies')
print(f'[INFO] Macro-only bounding area ~{count*macro_area_mm2:.2f} mm^2; excludes spacing, power, routing and other AI blocks')
print('[NOTE] No physical signoff, end-to-end neural inference or full ASIC GDS verified')

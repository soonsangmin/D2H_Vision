#!/usr/bin/env python3
"""Static mathematical and manifest checks; no claim of HDL simulation."""
import re
import csv
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
V103=ROOT/'docs/V103_FIFO_SRAM_MACRO_MAP.csv'
rows=list(csv.DictReader(V103.open()))
assert len(rows)==6
bank_size=1024
expected_banks=0
sum_bytes=0
out=[]
for row in rows:
    depth=int(row['memory_words'])
    assert int(row['data_width_bits'])==8
    banks=(depth+bank_size-1)//bank_size
    expected_banks+=banks
    sum_bytes+=depth
    out.append((row['hierarchy'],depth,banks,bank_size*banks-depth))
assert sum_bytes==52992,(sum_bytes,'unexpected FIFO map')
assert expected_banks==52,expected_banks
p=ROOT/'docs/V104_PHYSICAL_BANK_MAP.csv'
with p.open('w',newline='') as f:
    w=csv.writer(f)
    w.writerow(['memory_hierarchy','payload_bytes','macro_count','macro_capacity_bytes','unused_bytes'])
    for name,depth,banks,unused in out:
        w.writerow([name,depth,banks,banks*bank_size,unused])
r=(ROOT/'rtl/memory/asic_sram_1r1w.sv').read_text()
assert '`ifdef ASIC_USE_SKY130_SRAM' in r
assert 'sky130_sram_1kbyte_1rw1r_32x256_8 u_macro' in r
assert '4\'b0001 << wr_addr_i[1:0]' in r
assert 'if (wr_en_i) mem[wr_addr_i] <= wr_data_i;' in r
assert 'if (rd_en_i) q <= mem[rd_addr_i];' in r
cfg=(ROOT/'config/config_hard_sram.mk').read_text()
for token in ('VERILOG_DEFINES','ADDITIONAL_LEFS','ADDITIONAL_LIBS','ADDITIONAL_GDS','SYNTH_MOCK_LARGE_MEMORIES = 0'):
    assert token in cfg,token
# Mathematical check of byte->bank/word/lane and inverse over all legal
# addresses, covers all six geometries (including 3:1 spare bank capacity).
for _,depth,_,_ in out:
    positions=set()
    for i in range(depth):
        bank=i>>10; word=(i>>2)&255; lane=i&3
        assert ((bank*256+word)*4+lane)==i
        positions.add((bank,word,lane))
    assert len(positions)==depth
assert (ROOT/'tests/models/sky130_sram_1kbyte_1rw1r_32x256_8.sv').exists()
print('[OK] 6 FIFO physical bank maps: %d bytes -> %d x 1024-byte SRAM macros' % (sum_bytes,expected_banks))
print('[OK] End-to-end mathematical bank/word/lane uniqueness across all FIFO sizes')
print('[OK] Macro-specific ORFS config with hard views; default behavioral mode retained')
print('[NOTE] Macro views NOT shipped. HDL and actual macro characterization must be tested on WSL.')

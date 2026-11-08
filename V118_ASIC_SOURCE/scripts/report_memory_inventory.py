#!/usr/bin/env python3
"""Parse real Yosys/ORFS memory audit output into a trustworthy CSV.

Does not infer functionality from sizes and does not alter the design.
"""
from pathlib import Path
from collections import Counter
import re, csv, sys

source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output/audit/audit.log')
if not source.is_file():
    sys.exit(f'[ERROR] Audit log does not exist: {source}')
text = source.read_text(errors='replace')
pat = re.compile(r'^\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*([^|\n]+)\|', re.MULTILINE)
rows = []
for match in pat.finditer(text):
    depth, width, printed_bits, module = match.groups()
    module = module.strip()
    if not module.startswith('asic_ai_top'):
        continue
    depth, width = int(depth), int(width)
    rows.append((depth, width, depth * width, module))
if not rows:
    sys.exit('[ERROR] No memory inventory rows found; verify audit.log and the current synthesis build')

out = Path('output/audit/memory_inventory_v101.csv')
out.parent.mkdir(parents=True, exist_ok=True)
with out.open('w', newline='') as f:
    writer=csv.writer(f)
    writer.writerow(['depth', 'width', 'bits', 'KiB', 'module'])
    for depth, width, bits, module in sorted(rows,key=lambda r:r[2],reverse=True):
        writer.writerow([depth,width,bits,f'{bits/8192:.4f}',module])

bits=sum(r[2] for r in rows)
by_shape=Counter((r[0],r[1]) for r in rows)
large=sum(r[2] for r in rows if r[2] > 4096)
print('===== REAL MEMORY AUDIT INVENTORY (PRE-SYNTHESIS) =====')
print(f'Count             : {len(rows):,}')
print(f'Logical bits      : {bits:,}')
print(f'Logical size      : {bits/8192:,.2f} KiB ({bits/8/1024/1024:.4f} MiB)')
print(f'Largest memory    : {max(r[2] for r in rows):,} bits')
print(f'Bits in >4K banks : {large:,} (for sizing only)')
print('Top 20 memory shapes (count * depth * width):')
for (depth,width),n in sorted(by_shape.items(),key=lambda v:v[0][0]*v[0][1]*v[1],reverse=True)[:20]:
    print(f'{n:3d} x {depth:5d} x {width:4d} = {n*depth*width:10,d} bits')
reported = re.findall(r'Total inferred memories:\s*(\d+)',text)
if reported and len(rows) != int(reported[-1]):
    print(f'[WARNING] Parsed {len(rows)} rows vs reported {reported[-1]} - inspect log for repeated tables')
print('[NOTE] A Yosys log aggregate of 0 bits is a reporting artifact here, not physical SRAM consumption.')
print('[NOTE] This is logical memory inferred BEFORE PnR, not SRAM macro area or total physical chip area.')
print('[NOTE] Without per-instance hierarchy, identical shapes cannot be attributed to exact RTL instances.')
print(f'CSV               : {out}')

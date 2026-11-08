#!/usr/bin/env python3
"""Export 11 x 1024 x 96-bit weight ROM banks into 16-byte SDRAM records.
One 96-bit value per entry: low 64 bits at offset 0, high 32 bits + 32 pad
at offset 8. The CNN RTL in V1.02 DOES NOT yet read these images.
"""
from pathlib import Path
import csv, hashlib
ROOT=Path(__file__).resolve().parent.parent
IN=ROOT/'rtl/classifier/hex_weights'
OUT=ROOT/'output/weight_images'
OUT.mkdir(parents=True, exist_ok=True)
manifest=[]
for typ,n,base in [('exp',5,0x37000000),('proj',6,0x37100000)]:
    for bank in range(n):
        src=IN/f'{typ}_weight_bank1024_{bank}.hex'
        lines=[line.strip() for line in src.read_text().splitlines() if line.strip()]
        if len(lines)!=1024:
            raise ValueError(f'{src}: {len(lines)} lines, expected 1024')
        data=bytearray()
        for line in lines:
            if len(line)>24: raise ValueError(f'{src}: oversized 96-bit word')
            data.extend(int(line,16).to_bytes(16,'little'))
        target=OUT/f'{typ}_bank{bank}.bin'
        target.write_bytes(data)
        manifest.append([str(src.relative_to(ROOT)),str(target.relative_to(ROOT)),
                         f'0x{base+bank*0x4000:08X}',len(data),hashlib.sha256(data).hexdigest()])
with (OUT/'manifest.csv').open('w',newline='') as f:
    w=csv.writer(f);w.writerow(['source','image','base_address','bytes','sha256']);w.writerows(manifest)
print(f'[OK] Exported {len(manifest)} weight banks to {OUT}')
print('[NOTE] Data images only. CNN weight fetch is NOT migrated in V1.02.')

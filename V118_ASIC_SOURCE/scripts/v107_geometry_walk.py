#!/usr/bin/env python3
"""Software-only validation of address mapping, not HDL/silicon behavior."""
import csv
from pathlib import Path
from random import Random
root=Path(__file__).resolve().parents[1]
rows=list(csv.DictReader((root/'docs/V106_HANDSEG_BANK_CAPACITY.csv').open()))
assert len(rows)==8
random=Random(0x107)
for bank,row in enumerate(rows):
    depth=int(row['allocated_words'])
    blocks=(depth+511)//512
    mapped={}
    points={0,1,2,510,511,512,513,depth-2,depth-1}
    for _ in range(1500): points.add(random.randrange(depth))
    points={a for a in points if a>=0 and a<depth}
    for addr in sorted(points):
        tile=addr>>9; word=addr&511
        assert 0<=tile<blocks and 0<=word<512
        address=tile*512+word
        assert address==addr
        for lane in range(2):
            for copy in range(2):
                key=(copy,lane,tile,word)
                # Two 32-bit word lanes, two mirrored copies.
                assert key not in mapped
                mapped[key]=(addr,lane,copy)
    assert len(mapped)==4*len(points)
    print(f'PASS BANK_{bank}: {len(points)} legal 64b addresses -> {len(mapped)} unique macro-word lanes')
print('PASS: deterministic boundary + random software mapping check (not RTL simulation)')

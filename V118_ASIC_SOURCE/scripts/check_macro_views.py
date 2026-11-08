#!/usr/bin/env python3
"""Fail closed unless real macro LEF/Liberty/GDS views are installed.

This only checks basic consistency/format markers. It is NOT signoff verification.
"""
from pathlib import Path
import sys
import re

ROOT = Path(__file__).resolve().parent.parent
M = ROOT / 'macros' / 'sky130_1k'
NAME = 'sky130_sram_1kbyte_1rw1r_32x256_8'
files = {
    'LEF': M / (NAME + '.lef'),
    'Liberty': M / (NAME + '_TT_1p8V_25C.lib'),
    'GDS': M / (NAME + '.gds'),
}
errors=[]
for kind,path in files.items():
    if not path.is_file() or path.stat().st_size < 256:
        errors.append(f'{kind} missing, empty or too small: {path}')
if errors:
    print('[BLOCKED] Real SRAM macro views are not ready:')
    for e in errors: print(' -',e)
    print('See macros/sky130_1k/README.md; NEVER substitute a test stub for LEF/GDS/Liberty.')
    sys.exit(3)
lef=files['LEF'].read_text(errors='replace')
lib=files['Liberty'].read_text(errors='replace')
if not re.search(r'\bMACRO\s+'+NAME+r'\b',lef):
    errors.append('LEF has different MACRO name')
for pin in ('clk0','clk1','csb0','csb1','web0','wmask0','addr0','addr1','din0','dout1'):
    if not re.search(r'\bPIN\s+'+re.escape(pin)+r'(?:\[|\b)',lef):
        # May use bus pins in LEF with per-bit names. Keep as diagnostic, not blocker.
        if pin not in lef: errors.append(f'LEF missing expected port {pin}')
if NAME not in lib or 'cell' not in lib:
    errors.append('Liberty missing expected cell name')
if not re.search(r'\bSIZE\s+\d+(?:\.\d+)?\s+BY\s+\d+(?:\.\d+)?',lef):
    errors.append('LEF missing valid SIZE declaration')
# GDSII starts with 6-byte HEADER record (00 06 00 02), possibly 4-byte.
gds=files['GDS'].read_bytes()[:6]
if not (len(gds)>=4 and gds[2:4] == b'\x00\x02'):
    errors.append('GDS does not begin with standard HEADER record')
if errors:
    print('[BLOCKED] Macro views failed basic checks:')
    for e in errors: print(' -',e)
    sys.exit(3)
print('[OK] Basic macro view checks: names, LEF, Liberty, GDS header')
print('[NOTE] Still requires matching revision, PVT, physical PG, timing, LVS, DRC checks')

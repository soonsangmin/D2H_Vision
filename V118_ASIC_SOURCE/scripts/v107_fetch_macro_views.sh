#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MACRO=sky130_sram_2kbyte_1rw1r_32x512_8
REV=965df150c754fe2b3f93a0bd1f9883eb114279b2
BASE="https://raw.githubusercontent.com/VLSIDA/sky130_sram_macros/${REV}/${MACRO}"
DEST="macros/sky130_2k"
mkdir -p "$DEST"
for F in "${MACRO}.v" "${MACRO}.lef" "${MACRO}_TT_1p8V_25C.lib" "${MACRO}.gds" "${MACRO}.lvs.sp"; do
  echo "[DOWNLOAD] $F"
  curl --fail --location --retry 3 --retry-delay 2 "$BASE/$F" -o "$DEST/$F.tmp"
  mv "$DEST/$F.tmp" "$DEST/$F"
done
python3 - <<'PY2'
from pathlib import Path
p=Path('macros/sky130_2k')
name='sky130_sram_2kbyte_1rw1r_32x512_8'
expect={name+'.v':3000,name+'.lef':20000,name+'_TT_1p8V_25C.lib':12000,name+'.gds':1000000,name+'.lvs.sp':1000000}
for n,minsize in expect.items():
    assert (p/n).stat().st_size >= minsize, (n,(p/n).stat().st_size)
assert 'MACRO '+name in (p/(name+'.lef')).read_text(errors='replace')
assert 'module '+name in (p/(name+'.v')).read_text(errors='replace')
assert 'cell ('+name in (p/(name+'_TT_1p8V_25C.lib')).read_text().replace(' ','') or name in (p/(name+'_TT_1p8V_25C.lib')).read_text()
print('[OK] Physical SRAM views downloaded; basic sizes and names verified (NOT DRC/LVS/PVT signoff)')
PY2
sha256sum "$DEST/$MACRO".* "$DEST/${MACRO}_TT_1p8V_25C.lib" > "$DEST/SHA256SUMS.txt"
# V1.07 inherits the V1.04 1KiB CNN FIFO macro configuration; resolve
# these physical views too, so the ORFS manifest has no missing files.
CNN_MACRO=sky130_sram_1kbyte_1rw1r_32x256_8
CNN_BASE="https://raw.githubusercontent.com/VLSIDA/sky130_sram_macros/${REV}/${CNN_MACRO}"
CNN_DEST=macros/sky130_1k
mkdir -p "$CNN_DEST"
for F in "${CNN_MACRO}.lef" "${CNN_MACRO}_TT_1p8V_25C.lib" "${CNN_MACRO}.gds"; do
  echo "[DOWNLOAD] CNN macro $F"
  curl --fail --location --retry 3 --retry-delay 2 "$CNN_BASE/$F" -o "$CNN_DEST/$F.tmp"
  mv "$CNN_DEST/$F.tmp" "$CNN_DEST/$F"
done
python3 - <<'PY2'
from pathlib import Path
p=Path('macros/sky130_1k');n='sky130_sram_1kbyte_1rw1r_32x256_8'
assert (p/(n+'.lef')).stat().st_size>20000
assert (p/(n+'.gds')).stat().st_size>1000000
assert (p/(n+'_TT_1p8V_25C.lib')).stat().st_size>10000
print('[OK] CNN 1KiB macro views present (not full PVT/LVS/DRC signoff)')
PY2

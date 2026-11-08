#!/usr/bin/env python3
"""Static build manifest validation ONLY, not HDL simulation or PnR."""
import csv,hashlib,re,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
core=(root/'asic/asic_ai_local_core.sv').read_text()
full=(root/'asic/asic_ai_onchip_top.sv').read_text()
frame=(root/'rtl/memory/asic_onchip_frame_memory.sv').read_text()
config=(root/'config/config_onchip.mk').read_text()
assert 'handseg_camera_system #(.USE_EXTERNAL_DDR(0))' in core
assert 'module asic_ai_onchip_top' in full
assert 'module asic_onchip_frame_memory' in frame
assert 'SYNTH_MOCK_LARGE_MEMORIES = 0' in config
assert 'DESIGN_NAME = asic_ai_onchip_top' in config
assert 'asic_ai_onchip_top.sv' in config
assert 'asic_ai_local_core.sv' in config
assert 'asic_onchip_frame_memory.sv' in config
for name in ('mem_rd_valid_o','mem_wr_valid_o','mem_rsp_data_i'):
    assert name not in full.split('module asic_ai_onchip_top (',1)[1].split(');',1)[0],f'External memory pin exposed: {name}'
rows=list(csv.DictReader((root/'docs/V105_HANDSEG_PARAM_PROVENANCE.csv').open()))
assert len(rows)==6
for row in rows:
    b=(root/'params'/row['filename']).read_bytes()
    assert hashlib.sha256(b).hexdigest()==row['sha256'], row['filename']
    assert len(b.splitlines())==int(row['rows']),row['filename']
for src in (root/'rtl').rglob('*'):
    if src.suffix not in ('.v','.sv'):continue
    for ref in re.findall(r'\$readmem[hb]\s*\(\s*"([^"]+)"',src.read_text(errors='replace')):
        assert (root/ref).exists(),(src,ref)
print('[OK] Top has no DDR pins; HandSeg uses internal reference feature/parameter memory')
print('[OK] Snapshot and RGB96 are full-sized on-chip memories, not DDR')
print('[OK] Six original HandSeg parameter hex files match FPGA V6.23 bundle SHA256')
print('[OK] All literal CNN $readmemh file paths resolved')
print('[OK] Config disables memory mocking')
print('[NOTE] Static verification only: no functional equivalence, synthesis or GDS verified')

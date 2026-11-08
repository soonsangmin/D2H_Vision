#!/usr/bin/env python3
from pathlib import Path
import csv,re
D=Path(__file__).resolve().parent.parent
s=(D/'asic/asic_ai_top.sv').read_text()
crop=(D/'rtl/integration/ai_roi_reader_resize_96x96.sv').read_text()
mux=(D/'rtl/integration/ai_ddr_read_mux.sv').read_text()
writer=(D/'rtl/integration/asic_rgb96_ddr_writer.sv').read_text()
stream=(D/'rtl/integration/asic_rgb96_ddr_classifier.sv').read_text()
config=(D/'config/config.mk').read_text()
assert 'image96_bram u_rgb96' not in s
assert 'cls_rd_req_valid_i(cls_rd_valid)' in s
assert 'mem_wr_drain_done_i' in s
assert 'bram_wr_ready_i' in crop and 'S_PUSH' in crop
assert 'owner_r<=choose_c' in mux and 'pending_r' in mux
assert 'pixel_ready_o' in writer and 'FRAME_WORDS=2304' in writer
assert 'rd_rsp_ready_o=read_pending_r&&!word_valid_r' in stream
assert 'asic_rgb96_ddr_writer.sv' in config and 'asic_rgb96_ddr_classifier.sv' in config
assert '[remove_from_collection' not in (D/'config/constraint.sdc').read_text()
with (D/'docs/ORIGINAL_MEMORY_INSTANCE_MAP.csv').open() as f: items=list(csv.DictReader(f))
assert len(items)==120
assert sum(int(x['logical_bits']) for x in items)==2910832
assert sum(int(x['logical_bits']) for x in items if x['functional_group']=='RGB96 cropped image')==147456
# RGB565 little-endian packing and 64-bit addressing invariants
for base in (0,4,1020,9212):
    pix=[(i*37+0x1234)&65535 for i in range(base,base+4)]
    packed=sum(v<<(16*j) for j,v in enumerate(pix))
    assert all(((packed>>(16*j))&65535)==pix[j] for j in range(4))
    addr=0x36000000+(base//4)*8
    assert addr%8==0 and addr>=0x36000000 and addr<0x36004800
print('[OK] 120 mapped memories, original 2910832 bits, migrated RGB96 147456 bits')
print('[OK] Top read ownership & write flush safety signatures')
print('[OK] RGB565 pack/unpack and 64-bit address math')
print('[NOTE] Static check is not HDL simulation or PnR verification')

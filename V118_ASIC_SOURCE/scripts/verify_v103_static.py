#!/usr/bin/env python3
from pathlib import Path
import re
P=Path(__file__).resolve().parent.parent
f=(P/'rtl/classifier/stream_interstage_row_fifo_hwc_stage2.v').read_text()
r=(P/'rtl/memory/asic_sram_1r1w.sv').read_text()
h=(P/'rtl/memory/handseg_ddr_feature_memory.sv').read_text()
c=(P/'config/config.mk').read_text()
t=(P/'rtl/classifier/cnn_top.v').read_text()
assert 'asic_sram_1r1w #(' in f
assert 'rd_byte <= row_mem' not in f and 'row_mem[wr_mem_addr]' not in f
assert 'if (wr_en_i) mem[wr_addr_i] <= wr_data_i;' in r
assert 'if (rd_en_i) q <= mem[rd_addr_i];' in r
assert 'generate if (USE_LOCAL_SKIP_RAM)' in h and 'g_local_skip_disabled' in h
assert '/workspace/rtl/memory/asic_sram_1r1w.sv' in c
assert len(re.findall(r'stream_interstage_row_fifo_hwc_stage2\s*#\(',t))==6
print('[OK] Six CNN interstage FIFOs now share 1R1W synchronous SRAM interface')
print('[OK] Behavioral fallback SRAM read hold/old-data semantics preserved')
print('[OK] HandSeg inactive local RAM uses elaboration-time generate/tie-off')
print('[OK] ORFS source manifest includes 1R1W memory wrapper')
print('[NOTE] Static checks are NOT HDL simulation, physical macro mapping or GDS')

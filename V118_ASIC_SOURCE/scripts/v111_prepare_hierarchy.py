#!/usr/bin/env python3
"""Prepare V1.11 REAL AI top hierarchy check via sv2v + Yosys 0.64.

No RTL edits. No memory_map, memory shrinking, PnR or inference claims.
"""
from pathlib import Path
import shlex

root = Path(__file__).resolve().parent.parent
config = (root / 'config/config.mk').read_text()
lines = [s for s in config.splitlines() if s.startswith('export VERILOG_FILES = ')]
if len(lines) != 1:
    raise SystemExit('[FAIL] Cannot find unique VERILOG_FILES definition in config.mk')
base = shlex.split(lines[0].split(' = ', 1)[1])
extra = [
    'asic/asic_ai_local_core.sv',
    'asic/asic_ai_onchip_top.sv',
    'rtl/memory/asic_onchip_frame_memory.sv',
    'rtl/memory/v109_handseg_feature_sram_bank.sv',
    'rtl/memory/v109_handseg_feature_memory_macro.sv',
    'rtl/memory/sky130_sram_1kbyte_1rw1r_32x256_8_blackbox.v',
    'rtl/memory/sky130_sram_2kbyte_1rw1r_32x512_8_blackbox.v',
]
paths = []
for item in base + ['/workspace/' + x for x in extra]:
    path = item.removeprefix('/workspace/')
    if path not in paths:
        paths.append(path)
        if not (root / path).is_file():
            raise SystemExit(f'[FAIL] RTL file missing: {root / path}')

checks = {
    'asic_ai_onchip_top': ('asic/asic_ai_onchip_top.sv', 'asic_ai_local_core u_ai'),
    'detector in AI local core': ('asic/asic_ai_local_core.sv', 'handseg_camera_system #(.USE_EXTERNAL_DDR(0)) u_detector'),
    'HandSeg live': ('rtl/integration/handseg_camera_system.sv', 'handseg_live_top #('),
    'feature RAM in HandSeg live': ('rtl/integration/handseg_live_top.sv', 'reference_feature_memory #(.BANK0_INIT_FILE("")) u_mem'),
    'physical selection': ('rtl/memory/reference_feature_memory.sv', 'V109_SINGLE_COPY_SRAM'),
}
for label, (file, needle) in checks.items():
    if needle not in (root / file).read_text():
        raise SystemExit(f'[FAIL] Missing expected {label} instantiation in {file}')

package = 'rtl/config/handseg_config_pkg.sv'
if package not in paths:
    raise SystemExit('[FAIL] HandSeg package missing from source list')
paths = [package] + [p for p in paths if p != package]
out = root / 'output/v111_ai_top_hierarchy'
out.mkdir(parents=True, exist_ok=True)
(out / 'source_files.txt').write_text('\n'.join(paths) + '\n')
commands = [
    '# sv2v converts SystemVerilog package/import/packed structs to Verilog-2005',
    'read_verilog -defer /workspace/output/v111_ai_top_hierarchy/converted.v',
    'hierarchy -check -top asic_ai_onchip_top',
    'write_rtlil /workspace/output/v111_ai_top_hierarchy/ai_top_hierarchy.il',
    'stat -top asic_ai_onchip_top',
]
(out / 'elaborate.ys').write_text('\n'.join(commands) + '\n')
print('[PASS] V111: real AI top source path and manifest verified')
print('[INFO] Source files:', len(paths))
print('[INFO] Frontend: sv2v SystemVerilog conversion -> Yosys 0.64 read_verilog')
print('[INFO] Raw RTLIL export: no proc, no memory_map, no ABC, no OpenDB')
print('[INFO] Original RTL and existing SRAM/GDS checkpoints are unchanged')
print('[INFO] Hierarchy only; NO synthesis / memory_map / memory mocking / PnR')
print('[INFO] Output:', out)

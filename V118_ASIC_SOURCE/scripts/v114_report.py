#!/usr/bin/env python3
"""Checkpoint report, not tapeout certification; never claim a GDS that is absent."""
from pathlib import Path
import sys, datetime, json
ROOT=Path(__file__).resolve().parent.parent
O=ROOT/'output/v114_fullchip'
O.mkdir(parents=True, exist_ok=True)
state=(O/'status.txt').read_text().strip() if (O/'status.txt').exists() else 'NOT_STARTED'
synth=(O/'results/1_synth.odb')
gds=(O/'results/6_final.gds')
ins=(O/'inspect.log')
ins_text=ins.read_text(errors='replace') if ins.exists() else ''
checks={
  'HandSeg 2K macros after synthesis':'V114_POST_SYNTH_HANDSEG_2K=1128' in ins_text,
  'CNN 1K macros after synthesis':'V114_POST_SYNTH_CNN_1K=52' in ins_text,
  'OpenDB synthesis result':synth.is_file() and synth.stat().st_size>0,
  'GDSII streamout':gds.is_file() and gds.stat().st_size>0,
}
phases=['synth','floorplan','finish']
report=f'''# V1.14 — Báo cáo thực thi ASIC full-chip (SKY130HD)

**Thời điểm cập nhật:** {datetime.datetime.now().astimezone().isoformat(timespec='seconds')}

**Top:** `asic_ai_onchip_top` (HandSeg detector → ROI → CNN classifier)

**Trạng thái hiện tại:** `{state}`

## Bằng chứng trước lần chạy V1.14

- V1.09: tile 2 SRAM đã tạo GDSII (`output/v109_2macro/results/6_final.gds`).
- V1.10: toàn bộ subsystem 8 bank HandSeg có 1.128 SRAM 2KiB trong OpenDB.
- V1.11: hierarchy top AI khai báo 1.128 SRAM 2KiB và 52 SRAM 1KiB CNN.
- V1.12: residual engine đã qua regression stress với 513 writes, 257 backpressure.
- **Các kết quả trên KHÔNG phải GDSII của top AI.**

## Run full-chip V1.14

- Source: 68 RTL nguồn được chuyển bằng sv2v với `SYNTHESIS`, `ASIC_USE_SKY130_SRAM`, `V107_HARD_FEATURE_SRAM`, `V109_SINGLE_COPY_SRAM`.
- `SYNTH_MOCK_LARGE_MEMORIES=0`; không rút gọn RAM, không thay thế logic bằng stub.
- Die floorplan thử nghiệm: 30.000 × 30.000 µm = 900 mm². Chưa xác nhận khả năng tapeout/reticle.
- SRAM: 1.128 macro 2KiB và 52 macro 1KiB (yêu cầu post-synth phải khớp).
- ROM trọng số, snapshot và ROI vẫn được mô tả bằng inferred RTL memories; tool phải tổng hợp chúng thành mạch vật lý, nếu không sẽ **không có GDSII full-chip hợp lệ**.

## Kết quả có thể kiểm chứng

'''
for name,ok in checks.items():
    report+=f'- {"PASS" if ok else "CHƯA PASS"}: {name}.\n'
if gds.is_file():
    report+=f'\n- GDSII: `{gds.relative_to(ROOT)}` ({gds.stat().st_size:,} bytes)\n'
else:
    report+='\n- GDSII toàn chip: **chưa có**. Không sử dụng GDS tile để thay thế.\n'
report+='\n## Log và checkpoint\n\n'
for stage in phases:
    p=O/f'{stage}.log'
    if p.exists():
        report+=f'- `{p.relative_to(ROOT)}` — {p.stat().st_size:,} bytes\n'
for name in ['inspect.log','converted.v','results/1_synth.odb','results/2_floorplan.odb','results/6_final.gds']:
    p=O/name
    if p.exists():
        report+=f'- `{p.relative_to(ROOT)}`\n'
report+='''
## Signoff và giới hạn kỹ thuật

- **DRC:** chưa PASS. Các báo cáo trước có 154.466 markers chủ yếu bên trong macro OpenRAM 2KiB; không được bỏ qua.
- **LVS:** chưa kiểm tra ở full-chip.
- **STA:** chưa signoff đa corner.
- **Padframe / packaging / PDK manufacturing approval:** chưa xác minh.
- **Tương đương kết quả inference với FPGA:** chưa kiểm chứng toàn frame.
- Nếu tồn tại `6_final.gds` thì chỉ ghi nhận **GDSII physical trial**, không tuyên bố tapeout-ready.
'''
(O/'BAO_CAO_V114.md').write_text(report)
print(f'[REPORT] {O / "BAO_CAO_V114.md"}')
print('[RESULT]'+(' FULLCHIP_GDS_FILE_EXISTS' if checks['GDSII streamout'] else ' FULLCHIP_GDS_NOT_GENERATED'))

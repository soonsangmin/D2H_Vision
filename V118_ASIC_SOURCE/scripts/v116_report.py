#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime
r=Path(__file__).resolve().parent.parent
out=r/'output/v116_nearfull';out.mkdir(parents=True,exist_ok=True)
status=(out/'status.txt').read_text().strip() if (out/'status.txt').exists() else 'UNKNOWN'
gds=out/'results/6_final.gds';exists=gds.is_file() and gds.stat().st_size>0
lines=['# BÁO CÁO V1.16 — Near-full AI Compute-Only Physical Trial','',f'- Thời điểm lập: {datetime.now().astimezone().isoformat(timespec="seconds")}',f'- Trạng thái thực tế: **{status}**',f'- GDS tồn tại: **{"CÓ" if exists else "KHÔNG"}**',f'- Kích thước GDS: {gds.stat().st_size if exists else 0} bytes','',
'## Phạm vi được giữ lại','- Top gốc: `asic_ai_top`, không phải residual-only island.','- HandSeg: camera preprocessing, control/schedule, conv, residual, concat/upsample, GAP, ROI.','- Crop 96x96, snapshot sequencer, classifier MobileNet CNN 7-class, compute và điều khiển.','- Hard SRAM CNN 1KiB: dùng macro thật nếu còn trong netlist.','',
'## Phần bộ nhớ KHÔNG được hiện thực','- Snapshot/feature/parameters: chỉ giữ giao tiếp transaction 64-bit ra ngoài; KHÔNG có DDR PHY/controller hoặc memory storage trên die.','- `classifier_weight_rom96_banked`: module ROM được thay bằng macro NONFUNCTIONAL (không chứa trọng số).','- Payload của `handseg_async_pixel_fifo`: macro NONFUNCTIONAL; pointer/control logic giữ lại.','- Các RAM/ROM khác trong CNN/logic: theo RTL + hard 1KiB, chưa được signoff riêng.','',
'**CẢNH BÁO: GDS này KHÔNG CHỨA BỘ NHỚ CẦN THIẾT ĐỂ CHẠY INFERENCE. Không phải chip độc lập, không được gửi fab.**','Không có DRC/LVS/STA/tapeout signoff hoặc chứng minh end-to-end equivalence.','',
'## Các file kết quả',f'- GDS: `{gds.relative_to(r)}`' if exists else '- GDS: CHƯA XUẤT',
'- synth: `output/v116_nearfull/synth.log`','- floorplan: `output/v116_nearfull/floorplan.log`','- finish: `output/v116_nearfull/finish.log`',
'- inspect: `output/v116_nearfull/inspect.log`','']
if (out/'inspect.log').exists():
 lines+=['## Kiểm kê macro từ OpenDB','```',*(s for s in (out/'inspect.log').read_text(errors='replace').splitlines() if s.startswith('V116_')),'```']
(out/'BAO_CAO_V116.md').write_text('\n'.join(lines)+'\n')

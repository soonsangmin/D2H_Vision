#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime
r=Path(__file__).resolve().parent.parent
out=r/'output/v117_nearfull';out.mkdir(parents=True,exist_ok=True)
status=(out/'status.txt').read_text().strip() if (out/'status.txt').exists() else 'UNKNOWN'
gds=out/'results/6_final.gds'
exists=gds.exists() and gds.stat().st_size>0
lines=['# BÁO CÁO V1.17 — Near-Full AI Compute ASIC (NONFUNCTIONAL MEMORY)', '',f'- Lập lúc: {datetime.now().astimezone().isoformat(timespec="seconds")}', f'- Trạng thái thực: **{status}**',f'- GDSII có thật: **{"CÓ" if exists else "CHƯA"}**', f'- GDS bytes: **{gds.stat().st_size if exists else 0}**','', '## Phạm vi logic', '- Top: `asic_ai_top` từ source dự án, 61 source RTL, không phải bản demo một engine.', '- HandSeg: camera, preprocess, convolution/MAC, residual, concat/upsample, GAP, presence/ROI và FSM điều khiển.', '- Đường crop/resize 96×96, MobileNet CNN 7 block, GAP/FC classifier.', '- SRAM CNN 1KiB: hard macro nếu còn sau tổng hợp, xem `inspect.log`.','', '## Phần bộ nhớ thiếu / KHÔNG CHỨC NĂNG', '- Snapshot/feature/HandSeg parameter storage ra bus ngoài, không có DDR PHY/controller.', '- ROM CNN 96-bit: nonfunctional physical boundary (V1.16).','- FIFO pixel 24-bit: nonfunctional physical boundary (V1.16).', '- CNN 3x3 row buffer SRAM payload: nonfunctional physical boundary (V1.17); logic địa chỉ và chọn dữ liệu giữ lại.','- CNN residual vector SRAM payloads 192/256/512/1024-bit: nonfunctional physical boundary (V1.17); FSM và arithmetic giữ lại.','- RAM/ROM còn lại trong CNN có thể được Yosys tổng hợp thành standard cell; chưa bảo đảm timing/area.', '', '**QUAN TRỌNG: KHÔNG có khả năng chạy suy luận; không được gửi fab. Đây chỉ là thử nghiệm GDS của logic gần đầy đủ với các vùng lưu trữ chưa được hiện thực.**', '**Không có signoff DRC/LVS/STA và không có chứng minh tương đương với FPGA.**','', '## Kết quả theo giai đoạn']
for st in ('synth','floorplan','finish'):
 f=out/f'{st}.log';lines.append(f'- {st}: '+(f'{f.relative_to(r)} ({f.stat().st_size} bytes)' if f.exists() else 'NOT RUN'))
if exists:lines.append(f'- GDS: `{gds.relative_to(r)}`')
if (out/'inspect.log').exists():
 lines+=['','## Macro inventory từ OpenDB','```']+[x for x in (out/'inspect.log').read_text(errors='replace').splitlines() if x.startswith('V117_')]+['```']
(out/'BAO_CAO_V117.md').write_text('\n'.join(lines)+'\n')

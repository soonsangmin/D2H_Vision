# V1.16 — NEAR-FULL HANDSEG + CNN COMPUTE GDS — MEMORY OMITTED

## Cam kết phạm vi

- **Top dùng để tổng hợp: `asic_ai_top` GỐC**, không phải tile / residual-only island.
- **Giữ logic RTL nguyên bản** cho camera RGB565 → preprocessing → HandSeg (schedule, convolution, residual, upsample/concat, presence, ROI), đọc và resize crop 96x96, MobileNet CNN 7-class, kết quả classifier, arbiters và các bộ điều khiển.
- Giữ 52 SKY130 1KiB SRAM có trong CNN ở dạng hard macro *thật* nếu synthesis vẫn bảo toàn chúng; dữ liệu/model chỉ được kiểm tra ở cấp source, KHÔNG có formal equivalence.
- Top `asic_ai_top` **có giao tiếp transaction bộ nhớ 64-bit external** dùng cho snapshot, feature map và HandSeg parameters. Không gồm controller hay PHY DDR. Điều này đã là kiến trúc của top gốc; không phải tự thay thuật toán.
- Chỉ thay **payload lưu trữ** của: (1) `classifier_weight_rom96_banked` 96-bit CNN, (2) `handseg_async_pixel_fifo` 24-bit × 4096. Thay thế chỉ áp dụng trên `output/v116_nearfull` khi build; **source gốc không bị chỉnh sửa**. Điều khiển pointer/handshake FIFO giữ nguyên. 
- Để ORFS có thể place/route, các ô `v116_MISSING_*` dùng view giả lập vật lý **không hề chứa bit cell, không chứa transistor lưu trữ, không có chức năng**. GDS sinh ra dù thành công **không chạy inference được và không thể đem đi fab**. Cần thay ô đó bằng ROM/FIFO thật và bổ sung bộ nhớ ngoài trước khi triển khai silicon.
- Các bộ nhớ/ROM nhỏ còn lại trong các engine CNN có thể được Yosys biến thành logic tiêu chuẩn; **không mock** chúng.

## Chạy ngay trên WSL Ubuntu

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W

# Chỉ nếu V1.14 vẫn đang chạy:
docker ps --format '{{.Names}}' | grep '^v114_synth_' | xargs -r docker stop

python3 -m zipfile -e \
  /mnt/c/Users/tienh/Downloads/AI_ASIC_V116_NEAR_FULL_COMPUTE_GDS_PATCH.zip .

bash scripts/run_v116_nearfull_gds.sh gds
```

Script tự chạy `sv2v` → `ORFS synth` → OpenDB inventory → floorplan → placement / CTS / route → `6_final.gds`. Không chạy lại test engine hay DRC. Nếu lỗi, tự dừng, lưu stage và log, đồng thời xuất báo cáo.

## File kết quả thực tế nếu ORFS hoàn thành

- `output/v116_nearfull/results/6_final.gds` — **near-full compute-only with missing memory placeholders**, không phải working ASIC.
- `output/v116_nearfull/BAO_CAO_V116.md` — báo cáo cuối, kể cả trường hợp thất bại.
- `output/v116_nearfull/inspect.log` — số lượng macro sau synthesis (`CNN real SRAM`, `MISSING_WEIGHT_ROM`, `MISSING_FIFO_RAM`, logic).
- `output/v116_nearfull/synth.log`, `floorplan.log`, `finish.log`.

Nếu muốn kiểm tra synthesis riêng: `bash scripts/run_v116_nearfull_gds.sh synth`.

## Hạn chế

- Máy Docker RAM ~7.8 GiB, compute-only synthesis vẫn có thể rất nặng. Không có bảo đảm GDS hoàn thành kịp; bước trước thất bại vì `PROC_ARST` của bản full storage.
- Không có IO padframe, DDR controller/PHY, package, verification đầy đủ, timing signoff, DRC/LVS; các ô storage không hoạt động.
- Không gọi chip này là “FULL ASIC”, “working full inference”, “tapeout-ready”, “DRC clean”.
- **Không thay các macro bị thiếu bằng hằng số 0**, vì như thế Yosys có thể tối ưu bỏ nguyên mạng CNN.

## Báo cáo kĩ thuật

Dữ liệu thực tế trước V1.16: V1.10 OpenDB của 1128 SRAM HandSeg; V1.11 reachable hierarchy 1128 SRAM 2K và 52 SRAM 1K; V1.12 residual SRAM chức năng smoke/stress PASS; V1.14 full on-chip synthesis bị kẹt `PROC_ARST` và chưa xuất GDS. Đây là một nhánh COMPUTE-ONLY độc lập, không kế thừa claim GDS thành công của V1.14.

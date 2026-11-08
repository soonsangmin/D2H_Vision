# Báo cáo tiến độ ASIC HandSeg + CNN — mốc V1.12 / hướng V1.14

**Phạm vi thiết kế:** `asic_ai_onchip_top` — bộ phát hiện HandSeg, trích vùng ROI 96×96, bộ phân loại CNN 7 lớp. Mục tiêu: ASIC SKY130HD, lưu trữ nội bộ không DDR.

## Kết quả thực tế dựa trên log WSL do kỹ sư cung cấp

| Mốc | Kiểm tra | Kết quả |
| --- | --- | --- |
| V1.09 | Mô hình SRAM 1RW1R, single-copy, stress đơn vị, layout 2 SRAM | PASS, `6_final.gds` tile |
| V1.10 | Yosys/OpenDB subsystem 8 bank HandSeg | PASS, 1.128 SRAM 2KiB |
| V1.11 FAST | RTL hierarchy từ top `asic_ai_onchip_top` | PASS, 1.128 SRAM HandSeg + 52 SRAM CNN |
| V1.12 | `residual_word_engine` và V1.09 SRAM, smoke+stress | PASS, 513 writes, 257 throttled |
| V1.08 | KLayout DRC 4 SRAM tile | Hoàn tất, 154.466 violation markers nội bộ SRAM, NOT PASS |
| Full-chip | PnR/GDSII/STA/LVS/DRC signoff | CHƯA CÓ |

## Đánh giá hiện trạng

Bằng chứng hiện có đủ xác nhận **layout tile SRAM** và **top-level hierarchy** của hệ thống bộ nhớ. Chưa chứng minh được netlist ở mức gate toàn chip, GDSII chip AI, khả năng hoạt động end-to-end, hoặc tapeout signoff. SRAM physical chỉ là một phần: bộ nhớ tham số/trọng số HandSeg, CNN ROM, snapshot và RGB96 phải được triển khai vật lý thật và duy trì nội dung chính xác.

Khối SRAM feature HandSeg 1.128 macro chiếm khoảng **320,96 mm² ở mức macro-only** theo phân tích mốc V1.10. Điều này chưa bao gồm CNN, ROM và logic. Kích thước lớn không làm giảm yêu cầu giữ nguyên mô hình hoặc tuân thủ quy tắc PDK/foundry.

## Kế hoạch kết thúc V1.14

Chạy một luồng ORFS trên top đầy đủ, không chia lại bài test; lưu báo cáo tự động ở `output/v114_fullchip/BAO_CAO_V114.md`. Nếu có `results/6_final.gds`, đó là **GDSII physical trial chưa signoff**. Nếu không, báo cáo sẽ ghi đúng stage đã dừng và đường dẫn log; không báo cáo giả hoàn tất.

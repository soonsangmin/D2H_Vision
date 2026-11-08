# V1.11 FAST RTLIL: thay JSON + `proc` bằng xuất RTLIL trực tiếp

Lý do: Yosys 0.64 không có `read_slang`, nhưng đã PASS `sv2v` (68 source) và elaboration hierarchy. Khi thêm `proc` trước `write_json`, lượng `always`/array lớn trong AI khiến chạy hơn 1 giờ CPU gần 100% mà chưa tạo JSON. Lệnh `write_rtlil` hỗ trợ processes trực tiếp, nên không cần `proc` hoặc `memory_map`.

## Dùng

1. **Dừng V1.11 cũ** tại terminal đang chạy bằng Ctrl+C (hoặc `docker stop <container-id>` tại terminal thứ hai nếu cần). Chỉ dừng job V1.11, không động tới các Docker khác.
2. Giải nén ZIP này vào cùng root dự án V1.07/V1.09/V1.10 đã có. Nó thay 2 script, thêm 1 checker. Không sửa RTL, SRAM, ROM, GDS.
3. Chạy `bash scripts/run_v111_ai_hierarchy.sh`.

Sau `sv2v`, Yosys chạy `read_verilog -defer`, `hierarchy -check -top asic_ai_onchip_top`, `write_rtlil .../ai_top_hierarchy.il`, rồi `stat`. Python checker đi theo hierarchy từ AI top đếm các hard-macro thực sự được instantiate; không tính module định nghĩa không dùng. Kỳ vọng 1128 SRAM macro trong tám bank.

**Giới hạn:** Không chạy full synthesis, không chứng minh inference, không kiểm tra CNN/ROM thực tế, không GDS/DRC/LVS/STA. Nếu thất bại xem `output/v111_ai_top_hierarchy/elaboration.log` (Yosys) và thông tin in từ checker. Không nhầm số lượng instance đã elaborated với macro được giữ trong netlist sau synthesis.

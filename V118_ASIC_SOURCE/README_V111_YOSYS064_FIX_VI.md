# ASIC V1.11 — Sửa tương thích frontend Yosys 0.64+post

**Lỗi quan sát trong WSL:** `ERROR: No such command: read_slang`.

**Nguyên nhân:** `openroad/orfs:latest` trong máy chạy Yosys 0.64+post, không có frontend slang (`read_slang`). Đây là lỗi script V1.11 chứ không chứng minh RTL hoặc SRAM sai.

**Sửa:** Chỉ thay `scripts/v111_prepare_hierarchy.py`; sinh script dùng `read_verilog -sv -defer` hỗ trợ trên Yosys 0.64, đọc `rtl/config/handseg_config_pkg.sv` trước những source có `import`, rồi `hierarchy -check -top asic_ai_onchip_top`, xuất JSON và đếm SRAM reachable. Các define SRAM V1.09 giữ nguyên. Không sửa RTL, không chạy tổng hợp/gate mapping/PnR, không đụng kết quả V1.09/V1.10.

Cài đặt:

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V111_YOSYS064_COMPAT_PATCH.zip .
bash scripts/run_v111_ai_hierarchy.sh
```

Nếu còn lỗi ở frontend native (chẳng hạn một cú pháp SystemVerilog chưa được nó hỗ trợ), kiểm tra:

```bash
tail -n 50 output/v111_ai_top_hierarchy/elaboration.log
```

**Trạng thái xác minh:** Đã chạy Python source preflight trên đầy đủ 68 RTL file từ gói V1.07 + V1.09 + V1.11 và kiểm tra cú pháp script, thứ tự package/define. Chưa chạy Yosys 0.64 hoặc full AI hierarchy trong container này. Kết quả 1.128 hard SRAM reachable chỉ được coi PASS khi log WSL thực tế xác nhận.

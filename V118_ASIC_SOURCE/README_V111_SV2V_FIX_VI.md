# V1.11 — Sửa frontend SystemVerilog cho Yosys 0.64

## Nguyên nhân

`read_slang` không có trong ORFS/Yosys 0.64+post của máy người dùng. Thay bằng `read_verilog -sv` trực tiếp cũng không hợp lệ với RTL HandSeg: parser gặp `import handseg_config_pkg::*;` và dừng ở `concat_descriptor_rom.sv:6`.

## Giải pháp

Dùng công cụ độc lập **sv2v v0.0.13** để chuyển 68 file SystemVerilog (gồm package, typedef, import) sang một file Verilog-2005 tạm. Sau đó mới chạy Yosys `read_verilog -defer`, `hierarchy -check` và `write_json`. Binary sv2v được tự tải (chỉ lần đầu) từ asset Linux của GitHub upstream chính thức. Có thể dùng `SV2V_BIN=/path/to/sv2v` để tự chọn binary. Không đổi source RTL gốc, macro count kỳ vọng 1128, không memory_map, memory mocking hay PnR.

## Sử dụng

Từ thư mục gốc `AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W`, giải nén ZIP bản vá trực tiếp vào thư mục đó rồi chạy:

```bash
bash scripts/run_v111_ai_hierarchy.sh
```

Các file đầu ra nằm trong `output/v111_ai_top_hierarchy`: `converted.v`, `sv2v.log`, `elaborate.ys`, `elaboration.log`, và (nếu thành công) `ai_top_hierarchy.json`.

Nếu nhận `[FAIL] sv2v` hoặc `[FAIL] Yosys`, phần cuối log được in tự động. Không cần chạy lại V1.09/V1.10, cũng không chạy DRC.

## Giới hạn

Đã kiểm tra cú pháp Python/Bash và sinh script/source manifest trên source dự án. **Chưa xác nhận sv2v chạy thành công với đủ 68 file trên WSL**, chưa xác nhận hierarchy 1128 macro ở top AI, và chưa có functional inference/GDSII full-chip. Đây chỉ là bản sửa frontend, không phải bản sửa thuật toán.

Source: https://github.com/zachjs/sv2v/releases/tag/v0.0.13

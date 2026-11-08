# ASIC V1.03 — CNN FIFO SRAM boundary and HandSeg undriven cleanup

Mục tiêu: chuẩn hóa 6 FIFO HWC giữa các lớp CNN thành một giao tiếp RAM đồng bộ 1R/1W, **giữ nguyên dữ liệu và latency một chu kỳ**. Nhánh RAM skip HandSeg dùng DDR ngoài được tách bằng `generate`, không tạo tín hiệu `undriven` khi `USE_LOCAL_SKIP_RAM=0`.

## Thay đổi RTL

- `rtl/memory/asic_sram_1r1w.sv`: behavioral memory đầy đủ (không mock, không thu nhỏ), synchronous read với hold nếu `rd_en=0`, read-first khi đọc/ghi cùng địa chỉ.
- `rtl/classifier/stream_interstage_row_fifo_hwc_stage2.v`: thay truy xuất trực tiếp `row_mem[]` bằng instance `u_payload_sram`, giữ nguyên state và handshake HWC.
- `rtl/memory/handseg_ddr_feature_memory.sv`: `generate if USE_LOCAL_SKIP_RAM` giữ nguyên bốn local RAM; nhánh disable gán q=0. Không thay đổi giao thức DDR.
- `config/config.mk`: bổ sung module SRAM wrapper.
- `tests/reference_stream_interstage_row_fifo_v102.sv`: golden RTL FIFO chưa sửa, dùng đối chiếu cycle-by-cycle.
- Bốn bài cấu hình SRAM/FIFO và ba protocol testbench cũ được chạy bởi `scripts/run_v103_unit_tests.sh`.

## Dung lượng của sáu FIFO

B1→B2: 6.912 × 8 = 55.296 bit. Năm FIFO còn lại: 9.216 × 8 = 73.728 bit mỗi FIFO. Tổng: **423.936 bit = 51,75 KiB**. Bản V1.03 không giảm tổng số bit trong 6 FIFO; nó tạo interface để ánh xạ macro chính xác sau này.

## Chạy trên WSL

```bash
cd ~/asic_projects
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V103_CNN_FIFO_SRAM_BOUNDARY.zip .
cd AI_ASIC_V103_CNN_FIFO_SRAM_BOUNDARY
python3 scripts/verify_v103_static.py
bash scripts/run_v103_unit_tests.sh
bash scripts/run_screening_only.sh > screening_v103.log 2>&1
rc=$?; tail -n 45 screening_v103.log; echo EXIT_CODE=$rc
```

`run_screening_only.sh` vẫn thu nhỏ RAM để phát hiện lỗi frontend và **không phải PPA/GDS thật**. Đừng chạy `run_full.sh` cho ASIC đầy đủ ở bản này. Testbench mới là quy tắc đồng nhất theo chu kỳ, không xác minh inference CNN với ảnh thật. Muốn tapeout cần có SRAM macro tương ứng (LEF, Liberty, GDS, behavioral model); SRAM 6.912 hoặc 9.216 words phải được banking/tiling phù hợp macro công nghệ, sau đó chạy mô phỏng tương đương và DRC/LVS/STA.

## Bước kế tiếp

Dùng file `docs/V103_FIFO_SRAM_MACRO_MAP.csv` để chọn geometry/banking SRAM thật trên SKY130, sau đó áp dụng cùng interface cho `stream_row_buffer_3x3_parallel_hwc_stage2.v` và residual stores. Không thay thế CNN weight ROM bởi SDRAM chỉ bằng nối dây: ROM 96 bit 1-cycle phải có prefetch/cache và stall-aware scheduling.

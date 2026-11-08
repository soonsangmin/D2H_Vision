# ASIC V1.02 — chi tiết giao tiếp SDRAM và điều kiện nghiệm thu

## Thay đổi chức năng

- V1.01: `u_crop -> image96_bram(9216x16) -> classifier_rgb565_bridge -> cnn_ip_rgb_sobel`.
- V1.02: `u_crop(valid/ready) -> asic_rgb96_ddr_writer(4x16->64) -> external SDRAM at 0x36000000 -> asic_rgb96_ddr_classifier(64->4x16, valid/ready) -> cnn_ip_rgb_sobel`.
- Cả hai đều sử dụng **đúng CNN IP và weight** V6.23; chỉ thay nguồn RGB565 và timing handshake.
- Crop phải giữ một pixel khi writer stall. Writer chỉ chấp nhận 1 pixel khi `pixel_valid && pixel_ready`.
- CNN read bridge chỉ có một read outstanding, không cần bộ đệm toàn frame; chậm hơn bản FPGA và phải đo lại FPS.

## Memory-map byte address (logic boundary, KHÔNG phải JEDEC pins)

| Base | Chức năng | Byte usage |
| --- | --- | --- |
| `0x3200_0000` | input frame RGB565 snapshot | 614,400 bytes at 640x480x2 (depends on external host) |
| `0x3400_0000`... | HandSeg feature/weight/qparam region | existing bank allocator; may extend through 0x3490_0000 |
| `0x3500_0000` | classifier legacy reservation | not yet implemented |
| `0x3600_0000` | crop RGB565 output | `9216 x 2 = 18,432 bytes = 0x4800` |
| `0x3700_0000` | future CNN expansion-weight images | 5 banks × 16,384 bytes, 0x4000 stride |
| `0x3710_0000` | future CNN projection-weight images | 6 banks × 16,384 bytes, 0x4000 stride |

**Write ordering contract:** `mem_wr_ready_i` only acknowledges acceptance, not DRAM visibility. External adapter must provide `mem_wr_drain_done_i` high when accepted writes have become visible to subsequent reads. Keeping it tied high is UNSAFE if writes may be buffered. DDR controller and DDR PHY are not included. External read response must be precisely one per accepted request, stable until response handshake, and delayed at least one cycle (no zero-latency response), using 64-bit little-endian byte ordering.

## RTL source changes

- `rtl/integration/ai_roi_reader_resize_96x96.sv`: adds input `bram_wr_ready_i`; holds pixel in `S_PUSH`, advances source/dest counters only on writer handshake.
- `rtl/integration/asic_rgb96_ddr_writer.sv`: packs pixel0→`[15:0]`, pixel1→`[31:16]`, etc. Writer accepts no new pixels while write valid waits for `mem_wr_ready_i`. On last pixel, signals `finished_o` only after all 2304 words accepted.
- `rtl/integration/asic_rgb96_ddr_classifier.sv`: reads 2304 words and unpacks them to 9216 pixels, waits for `rgb_ready` each pixel and for memory read response when necessary.
- `rtl/integration/ai_ddr_read_mux.sv`: owner locked while request outstanding. Classifier is third client, enabled in ASIC top.
- `asic/asic_ai_top.sv`: removed instance `image96_bram`, added SDRAM write arbiter and memory flush barrier.

## Chưa hoàn thành (KHÔNG được xem đã GDS-ready)

- 119 memory instances khác còn trong RTL (thực tế cần **chạy lại audit**, một số ROM constant không được đếm trong báo cáo cũ).
- CNN weight ROM 11 banks × 1024 × 96 bit **chưa** chuyển sang SRAM macro / DDR fetch. File binary chỉ là ảnh data dùng về sau. ROM constant có thể không được đếm là inferred RAM.
- CNN line/row buffers, HandSeg weight group cache, CDC FIFO, reset warnings, and HandSeg undriven warnings chưa xử lý.
- Nhiều RAM cần đa cổng song song, không thể chuyển trực tiếp thành read/write một giao dịch/chu kỳ mà không thay scheduling của CNN.
- Chưa mô phỏng tương đương RTL V6.23 / V1.02 để xác minh số lớp ra chính xác.
- Chưa chạy Yosys synthesis thật/STA/PD/DRC/LVS trên môi trường của user.

## Thứ tự kiểm chứng

1. `python3 scripts/verify_v102_static.py` — kiểm tra cấu trúc/inventory.
2. `bash scripts/run_unit_tests.sh` — test writer 9216 pixel và owner lock arbiter bằng Icarus trên Ubuntu.
3. `bash scripts/run_screening_only.sh` — mock các bộ nhớ lớn, để kiểm tra Slang/Yosys/OpenSTA. Không dùng sản phẩm làm chip thật.
4. Dựng testbench tích hợp crop↔external DRAM↔classifier, đối chiếu từng pixel và class label với V6.23 (chưa cung cấp).
5. Phân loại SRAM macro/DDR rồi thực hiện memory replacement lần lượt, cuối cùng physical design.

- `crop_alignment_error_o` là output kiểm tra sai thứ tự pixel hoặc thiếu pixel ở RGB96 writer. Nếu báo lỗi, hệ thống sẽ không cho classifier bắt đầu.

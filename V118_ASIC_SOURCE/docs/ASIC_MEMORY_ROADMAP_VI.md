# V1.01 — Memory audit và định hướng external SDRAM

## Mốc đo thực tế (từ audit của người dùng)

- `120` inferred memory instances.
- `2,910,832` logical memory bits = `355.33 KiB`.
- Lớn nhất: `9,216 x 16 = 147,456` bit (`18 KiB`).
- `SYNTH_MEMORY_MAX_BITS=4096` là giới hạn phòng ngừa Yosys ánh xạ bộ nhớ lớn sang FF; `FAIL` ở đây là kết quả dự kiến của *audit*. Không có GDS.
- Dòng `Total inferred memory bits (all instances): 0` không khớp bảng. Tổng đúng được tính từ 120 hàng như trên. Để tái tạo bảng chạy `python3 scripts/report_memory_inventory.py`.

## Source provenance

`SOURCE_PROVENANCE.csv` mô tả source V1.00: 230 file, 228 `modified=no`, hai thay thế ASIC: `classifier_weight_rom96_banked.sv` và `image96_bram.sv`. V1.01 bổ sung sửa *thứ tự khai báo* `OUT_LANE_W` trong `pw_engine_project.v`, không thay đổi đường dữ liệu.

## Thực tế kiến trúc

- `asic/asic_ai_top.sv` đã có cổng `mem_rd_*`, `mem_rsp_*`, `mem_wr_*` dạng **64-bit transaction, 32-bit byte address, valid/ready**. Đây không phải chân JEDEC SDRAM vật lý.
- `rtl/integration/image96_bram.sv` vẫn là RAM đồng bộ đọc 1 chu kỳ `9,216 x 16`; đang nối trực tiếp `u_crop` với `classifier_rgb565_bridge`. Muốn đưa RA DRAM ngoài cần logic write, read-buffer và ready/valid, vì `classifier_rgb565_bridge` mặc định đọc sync RAM đúng 1 chu kỳ.
- `rtl/classifier/classifier_weight_rom96_banked.sv` tạo ROM bằng `$readmemh`, 11 bank khai báo `1024 x 96` trong hai nhóm expansion/projection. Lúc làm ASIC cần định địa chỉ trọng số, adapter xếp dữ liệu 96-bit từ đường 64-bit và prefetch/ready, hoặc dùng ROM macro thật; chỉ kéo dây ra DDR **không đủ**.
- `rtl/classifier/stream_interstage_row_fifo_hwc_stage2.v` và `rtl/memory/handseg_weight_group_ram.sv` dùng RAM đồng bộ cho dataflow. Nhiều FIFO/line buffer đòi throughput cao: cân nhắc SRAM macro tại chip, hoặc đổi microarchitecture theo scheduling với DRAM DMA + cache.
- `rtl/integration/ai_ddr_read_mux.sv`: tại top `classifier_select_i=0` và `cls_rd_req_valid_i=0`. Chưa có đường giao dịch DDR dành cho classifier. Hệ thống V1.00 **chưa** thể load trực tiếp trọng số CNN từ DDR ngoài.
- Một phần dữ liệu SDRAM (HandSeg params / ảnh snapshot) phải được host pre-load trước mỗi inference như nêu trong tài liệu V1.00.

## Kế hoạch chuyển đổi không làm sai AI

1. Đóng băng bản RTL V6.23 làm golden reference. Xác lập testbench kiểm tra pixel/ROI/class ID và dữ liệu weight bit-exact.
2. Phân loại 120 bộ nhớ theo chức năng, port, latency, bandwidth và cơ chế reset. Bảng `depth x width` **không đủ** để ánh xạ chính xác toàn bộ về instance.
3. Thêm một memory controller client cho classifier. Cơ chế arbitration **phải giữ ownership cho response của từng request**, tránh chuyển selector khi DDR response chưa trả về. Bắt buộc xét read backpressure và write-data consistency.
4. Với ROM trọng số CNN: load vào SDRAM khi boot; DMA/prefetch vào SRAM cache hoặc xếp word trong FIFO trước khi MAC chạy, giữ đúng thứ tự và độ rộng 96-bit.
5. Với frame 96x96: chọn SRAM macro tại chỗ hoặc stream frame vào SDRAM và refill buffer; `classifier_rgb565_bridge` phải dùng valid/ready response, không giả định độ trễ 1 chu kỳ.
6. Với line buffers và feature maps: SRAM macro nhiều bank nếu cần các đọc/ghi song song; nếu off-chip thì phải xác minh bandwidth và scheduling.
7. Chạy simulation/equivalence ở nhiều frame với golden V6.23, rồi mới synth/P&R thật. Dùng macro có bộ views LEF/GDS/Liberty/SPICE. Sau GDS cần STA corners, LVS, DRC, power, I/O, pads và kiểm tra DDR PHY/controller riêng.

## Lệnh tiếp theo

```bash
cd ~/asic_projects/AI_ASIC_V101_MEMORY_ANALYSIS_AND_SCREENING
python3 scripts/report_memory_inventory.py
# TUY CHON: screening synthesis, mock các RAM >4Ki bits, không tạo chip hợp lệ
bash scripts/run_screening_only.sh
```

**Cảnh báo:** `SYNTH_MOCK_LARGE_MEMORIES=1` sẽ thay đổi logic bộ nhớ, *không được dùng output screening để công bố diện tích/timing/GDS ASIC hoàn chỉnh*.

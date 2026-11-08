# AI V6.23 → ASIC toàn chuỗi: HandSeg + Crop96 + CNN (SKY130HD)

## Đã thực hiện trong v1.00

- Giữ **nguyên các module thuật toán thực tế** từ V6.23: `handseg_live_top`/các engine, camera preprocessing, crop ROI, CNN RGB565+Sobel, mạng CNN và bộ giải mã class.
- Xây `asic_ai_top.sv` mới thay cho `DE10_NANO.sv`, không instantiate `soc_system`, `clock_gen`, `altsyncram` Cyclone V hay HDMI IP.
- Thay `image96_bram.sv` bằng RAM RTL đồng bộ 9216×16 để có thể tổng hợp bằng Yosys. **Đây không phải macro SRAM thật**; có thể bùng nổ diện tích nếu tổng hợp sang FF.
- Thay ROM M10K `classifier_weight_rom96_banked.sv` bằng ROM đọc HEX đồng bộ, dùng đúng file trọng số V6.23 và thời gian đọc một chu kỳ. **ROM 11 bank × 1024 × 96 bit là rất lớn** khi map sang standard cells.
- Giữ `handseg_ddr_memory_subsystem` và `ai_ddr_read_mux` dùng 64-bit ready/valid; đưa các tín hiệu qua chân module ASIC top.
- Dùng chung một clock ngoài `clk_i` cho camera, detector, crop và CNN để thử ASIC đầu tiên. Chuyển `cam_frame_start_i` thành xung frame-start ở miền clock này.
- Bỏ đường HDMI/OV3660 physical control/7-segment/HPS. Kết quả ROI/classifier vẫn có chân số logic ra ngoài ASIC top; HDMI/camera chip ngoại vi có thể kết nối sau.

## Bộ nhớ ngoài: giao tiếp giao dịch, KHÔNG phải SDRAM PHY

`mem_rd_valid_o`, `mem_rd_ready_i`, `mem_rd_addr_o[31:0]`,
`mem_rsp_valid_i`, `mem_rsp_ready_o`, `mem_rsp_data_i[63:0]`;
`mem_wr_valid_o`, `mem_wr_ready_i`, `mem_wr_addr_o[31:0]`,
`mem_wr_data_o[63:0]`.

- Dữ liệu 64-bit và địa chỉ byte little-endian; phía ngoài có controller đảm bảo thứ tự response, duy trì valid cho đến khi ready, và chấp nhận mỗi write tại cạnh clock khi valid&&ready.
- `HANDSEG` vẫn chờ magic `0x48534731` tại DDR `0x349FF000` (nguyên cơ chế `parameter_store_ddr_v141`). Trọng số và quantization tensors phải được host nạp đúng layout gốc.
- ROI cropper đọc RGB565 snapshot 640×480 từ `0x3200_0000`. **Tập ảnh snapshot phải được nạp trước khi frame được cho phép và không được ghi đè trước `classifier_done_o`.** Trong bản này không có camera DMA writer vào snapshot SDRAM: đây là một yêu cầu đối với hệ thống ngoại vi; khác đường camera→DDR ở bo FPGA.
- Các bank feature maps của HandSeg dùng base `0x3400_0000`, stride `0x0010_0000` và các vùng weight/qparam theo source gốc.

Phần chân giao dịch phía trên phù hợp để **tổng hợp một accelerator ASIC core**. Nó không thể nối thẳng với chân DDR3 DQ/DQS/CK/CA của chip SDRAM vật lý. Khi thiết kế phần cứng hoàn chỉnh bắt buộc có memory controller, PHY/macro IO, clocking/calibration, pad ring và signoff SI/PI.

## Kỹ thuật chưa đủ điều kiện tapeout

1. Cần chạy tổng hợp thực trên máy có ORFS/Yosys để phát hiện unsupported HDL và kiểm tra cell count/area; bộ ZIP này được kiểm tra tĩnh, **chưa chạy synthesis/place-route**.
2. Cần kiểm tra mô phỏng bit-exact RTL giữa DE10 bản gốc và ASIC top với dữ liệu DDR snapshot và weights y hệt; chưa xác minh ở đây.
3. RAM và ROM lớn hiện dùng behavioral infer/memory_map; không có SRAM/ROM macro SKY130 tương ứng trong GDS. Full standard-cell flow có thể mất rất nhiều RAM/CPU, gặp lỗi placement/routing. Cần kế hoạch macro SRAM hoặc đưa ROM classifier sang giao tiếp memory có backpressure và DMA/prefetch.
4. Chưa làm DRC, LVS, extracted STA, power signoff, scan/DFT, pad ring, analog PHY, ESD, clock/reset IO.
5. Ràng buộc clock 100ns chỉ để thử, **không phải 50MHz/20ns signoff**.

## Cách chạy trên WSL2/Ubuntu có Docker ORFS sẵn

Trên Windows tải ZIP và giải nén vào `~/asic_projects/` rồi trong **Ubuntu WSL**:

```bash
cd ~/asic_projects/AI_ASIC_V100_FULL_HANDSEG_CNN_EXTERNAL_DDR_SKY130
# Nên chạy audit bộ nhớ trước để tránh tổng hợp nhiều RAM khổng lồ:
bash scripts/run_memory_audit.sh
# Chạy full synthesis không mock; rất nặng, có thể bị giới hạn bởi RAM/CPU:
bash scripts/run_synth_only.sh
```

ORFS mặc định giới hạn 4096 bit cho một inferred memory; dự án ASIC tăng `SYNTH_MEMORY_MAX_BITS` lên 1048576 để khảo sát bộ nhớ **thật**, không dùng fake/mocked memory. Đây không có nghĩa khả năng P&R được đảm bảo. Nếu gặp `memory limit`, `OOM`, hoặc netlist quá lớn, cần thay bộ nhớ thành SRAM macro hoặc thiết kế external memory interface với đúng latency/backpressure, **không được bật `SYNTH_MOCK_LARGE_MEMORIES=1` rồi công bố GDS đó là chip AI đầy đủ**.

Nếu synthesis thành công mới chạy:

```bash
bash scripts/run_full.sh
find output -name '*.gds' -o -name '*.def' -o -name '*.spef'
```

Các file log trong `output/` được lưu trên WSL, không mất khi Docker container --rm thoát.

**Không thay thế/ghi đè project Quartus V6.23 đang chạy ổn định.** ASIC là nhánh kế thừa; FPAG golden source chỉ được sao chép, không chỉnh sửa.

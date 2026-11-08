# V1.05 — Mục tiêu toàn bộ AI trên ASIC SKY130, không dùng DDR ngoài

**Tình trạng:** Đã tạo source RTL **ứng viên** cho full-onchip HandSeg → ROI crop → CNN. Chưa có bằng chứng full end-to-end simulation, synthesis toàn chip, STA, DRC/LVS hoặc GDSII. Đây KHÔNG PHẢI file ASIC hoàn thiện để fab.

## Thay đổi so với V1.04

1. Bản gốc `asic/asic_ai_top.sv` được giữ lại để đối chiếu. Bản `asic/asic_ai_local_core.sv` chọn `USE_EXTERNAL_DDR(0)` trong `handseg_camera_system`. Nhánh đã có sẵn trong FPGA V6.23 bao gồm `reference_feature_memory` (8 bank × 131072 × 64 bit) và `parameter_store_v141` tải trọng số/quantization từ sáu tập tin `params/*.hex`.
2. Từ ZIP FPGA V6.23 gốc, đã chép đúng sáu file HEX HandSeg (bao gồm 122.478 word 64-bit trọng số và 1.261 group quantization); CSV `docs/V105_HANDSEG_PARAM_PROVENANCE.csv` lưu SHA256. Trọng số chỉ là ROM có giá trị khởi tạo ở mức RTL; SRAM thông thường **không bảo toàn giá trị khi tắt nguồn**. Phải chứng minh weight ROM được synthesis thành logic ROM cố định hoặc thiết kế ROM macro trước tapeout.
3. `rtl/memory/asic_onchip_frame_memory.sv` lưu riêng snapshot 640×480 RGB565 (`76800 × 64 bit = 600 KiB`) và ROI 96×96 (`2304 × 64 bit = 18 KiB`). Snapshot ghi từ luồng camera khi frame gate cho phép; ROI ghi từ writer hiện có, đọc theo handshake đúng thứ tự. Bộ nhớ không bị thu nhỏ.
4. `asic/asic_ai_onchip_top.sv`: **không có chân DDR** ở top; chỉ nhận camera RGB565, clock/reset và trả trạng thái/kết quả detector/CNN. Sáu FIFO CNN hard SRAM giữ nguyên nhánh V1.04 và sử dụng LEF/Liberty/GDS thật nếu chạy `config_onchip.mk`.
5. `config/config_onchip.mk` vô hiệu hóa `SYNTH_MOCK_LARGE_MEMORIES`. **Không** tạo netlist giả để có GDS.

## Kiểm tra nhanh với WSL

Giải nén ZIP tại `~/asic_projects`, sau đó:

```bash
cd ~/asic_projects/AI_ASIC_V105_FULL_ONCHIP_RTL
python3 scripts/verify_v105_static.py
bash scripts/run_v105_unit_tests.sh
```

Icarus test chỉ kiểm tra ảnh snapshot/ROI, KHÔNG phải test classifier 7 lớp. Bộ test HandSeg + CNN end-to-end với golden FPGA vẫn phải xây dựng.

## Kết nối macro vật lý

Các macro SRAM 1 KiB đã tải vào V1.04 trên WSL, không đóng gói lại trong V1.05. Sao chép toàn bộ view vật lý thật từ V1.04:

```bash
cp -a ../AI_ASIC_V104_SKY130_SRAM_MACRO_BANKING/macros/sky130_1k/*.lef macros/sky130_1k/
cp -a ../AI_ASIC_V104_SKY130_SRAM_MACRO_BANKING/macros/sky130_1k/*.lib macros/sky130_1k/
cp -a ../AI_ASIC_V104_SKY130_SRAM_MACRO_BANKING/macros/sky130_1k/*.gds macros/sky130_1k/
python3 scripts/check_macro_views.py
```

## Rào cản còn lại trước khi có ASIC GDSII thật

- **Bộ nhớ 8 MiB của `reference_feature_memory` là kiến trúc tham chiếu FPGA**, không phải phân bổ macro vật lý tối ưu. Chỉ tính riêng bộ nhớ này đã có 67.108.864 bit. Nếu dùng SRAM 1 KiB mỗi bank thì cần **8192 macro** — không phù hợp một die SKY130 thực tế; phải giảm chiều sâu theo access range từng bank hoặc chọn macro lớn và re-bank.
- Các RAM snapshot, ROI, line buffer, residual và FIFO chưa được mapping hoàn toàn sang hard macro phù hợp throughput. Config hiện chọn SRAM macro cho sáu FIFO, các RAM khác vẫn là inferred RAM.
- ROM weights HandSeg và CNN phải được tổng hợp thành logic/cell ROM có giá trị nonvolatile đã kiểm tra. Không thể dùng SRAM chưa được nạp rồi gọi đó là weights nội bộ.
- Chưa chạy top-level functional regression, không có I/O padframe, SRAM macro PDN, macro floorplan, STA, DRC/LVS, GDS streamout.
- `scripts/run_v105_full_synth.sh` cố tình chặn nếu chưa xác nhận rủi ro; có thể chạy THỬ với `I_UNDERSTAND_FULL_ONCHIP_COST=YES bash scripts/run_v105_full_synth.sh` nhưng dễ tiêu hao rất nhiều RAM/CPU và kết quả synth, nếu thành công, vẫn chưa đạt PnR.

## Mục tiêu phát triển duy nhất tiếp theo

Phải thay `reference_feature_memory` tham chiếu thành các SRAM bank sâu thực sự cần thiết theo max access của mô hình, ánh xạ ảnh snapshot/ROI và các line buffer, sau đó làm golden-image equivalence, synth, floorplan, place/route, STA/DRC/LVS và xuất GDSII. Không lặp lại các bản vá chỉ đếm SRAM.

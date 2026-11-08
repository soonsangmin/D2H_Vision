# ASIC V1.04 — SKY130 hard-SRAM banking, chưa phải tapeout

## Tình trạng được chứng minh

V1.03 từ log người dùng: HDL unit SRAM 1R1W PASS; bốn cấu hình FIFO equivalence PASS; 3 protocol DDR PASS; *screening* Yosys/OpenROAD PASS (EXIT_CODE=0). Screening có MOCK RAM nên không phải netlist chức năng thật.

V1.04 triển khai phần tiếp theo: 6 FIFO HWC CNN sử dụng `asic_sram_1r1w` với nhánh tùy chọn `ASIC_USE_SKY130_SRAM`. Nhánh mặc định vẫn là bộ nhớ đầy đủ RTL V1.03 và không thay đổi thuật toán CNN/HandSeg. **Nhánh hard-macro chưa được kiểm thử HDL trên máy tạo ZIP; cần chạy WSL.**

## Macro được chọn cho nhánh thử nghiệm

Tên: `sky130_sram_1kbyte_1rw1r_32x256_8`. Macro OpenRAM có 256 word x 32 bit = 1024 byte, 1 cổng RW (dùng để ghi), 1 cổng R; mask ghi theo 8-bit. Cần cung cấp bộ view chính xác tương ứng trong `macros/sky130_1k/`:

- `sky130_sram_1kbyte_1rw1r_32x256_8.lef`
- `sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib`
- `sky130_sram_1kbyte_1rw1r_32x256_8.gds`

**Không có view vật lý thực trong gói.** Test Verilog stub `tests/models/...` chỉ để xác minh giao thức và banking, KHÔNG được dùng cho physical design. Macro được tham khảo từ tài liệu tích hợp: https://openlane.readthedocs.io/en/2023.09.07/tutorials/openram.html và ORFS variables https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html.

## Byte address mapping (không đổi thứ tự HWC)

Khi RTL `wr_addr_i`/`rd_addr_i` là địa chỉ **byte** tuyến tính:

- `bank = address >> 10` (mỗi bank chứa 1024 byte)
- `word = (address >> 2) & 8'hFF` (256 word/bank)
- `lane = address[1:0]` (4 byte/word)
- `din0 = {4{wr_data_i}}`, `wmask0 = 4'b0001 << lane`, `web0=0`.
- `dout1[8*lane +: 8]` là byte đọc; latch bank/lane theo `rd_en_i`.
- Khi `rd_en_i=0`, wrapper giữ lại byte đọc cuối qua một thanh ghi vì model OpenRAM có thể làm `dout1` trở thành X tại cạnh clock nếu chip-select không tích cực.

Đường đọc chịu timing thực của macro (output không phải lúc nào cũng có ngay sau posedge như model RTL). Nhánh thực vẫn phải được xác minh bằng **mô hình gốc OpenRAM và STA Liberty** trước khi gắn với CNN.

**Same-word concurrent R/W**: dữ liệu không được bảo đảm trên macro thực. Wrapper phát `$fatal` ở simulation nếu cùng clock vừa đọc vừa ghi cùng word 32-bit. FIFO completed-row theo thiết kế chỉ đọc row đã ghi xong; kiểm thử đầy đủ và formal proof ở hệ thống là cần thiết.

## Tính toán bank

Dựa trên sáu instance được rà soát trong `docs/V103_FIFO_SRAM_MACRO_MAP.csv`:

| FIFO | Dữ liệu | Macro 1 KiB | Dung lượng provision |
|---|---:|---:|---:|
| B1 -> B2 | 6.912 byte | 7 | 7.168 byte |
| B2 -> B3 | 9.216 byte | 9 | 9.216 byte |
| B3 -> B4 | 9.216 byte | 9 | 9.216 byte |
| B4 -> B5 | 9.216 byte | 9 | 9.216 byte |
| B5 -> B6 | 9.216 byte | 9 | 9.216 byte |
| B6 -> B7 | 9.216 byte | 9 | 9.216 byte |
| **Tổng** | **52.992 byte (51,75 KiB)** | **52** | **53.248 byte (52 KiB)** |

**Cảnh báo diện tích:** LEF ví dụ trong OpenLANE ghi một macro 479,78 x 397,5 µm. Nếu bộ view của bạn đúng geometry này thì 52 macro riêng đã có tổng diện tích cell khoảng **9,917 mm²**, chưa tính halo, routing, power grid và logic AI. Do đó giải pháp **không phù hợp với mục tiêu chip rất nhỏ (ví dụ Tiny Tapeout vài tile)**. Cần so sánh diện tích thực của macro view hoặc chọn kiến trúc cache/SDRAM khác trước khi commit layout.

Từ audit ban đầu 2.910.832 bit inferred RAM: RGB96 đã chuyển 147.456 bit ra DDR ở V1.02 và sáu FIFO chuyển 423.936 bit ra hard-macro trong cấu hình V1.04; từ số audit gốc còn **~2.339.440 bit (~285,58 KiB) các RAM khác cần ánh xạ**, chưa kể trọng số ROM hoặc tối ưu của tổng hợp. Con số này là **chênh lệch trên audit cũ**, không phải báo cáo một lần tổng hợp V1.04 thật.

## Chạy WSL: ưu tiên unit test

```bash
cd ~/asic_projects
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V104_SKY130_SRAM_MACRO_BANKING.zip .
cd AI_ASIC_V104_SKY130_SRAM_MACRO_BANKING
python3 scripts/verify_v104_static.py
bash scripts/run_v104_unit_tests.sh
```

Lệnh unit test gồm toàn bộ V1.03 regression, sau đó bật `-DASIC_USE_SKY130_SRAM` với **mô hình mô phỏng giao thức** ở `tests/models` và kiểm tra 2.083 byte trên 3 bank cũng như 5 cấu hình FIFO (gồm WIDTH 96/CHANNELS 32). PASS ở đây không thay thế việc đo timing với cell thật.

## Tích hợp macro physical riêng biệt (chỉ sau khi có views)

```bash
python3 scripts/check_macro_views.py
# Chỉ khi đã đặt LEF/Liberty/GDS THẬT vào macros/sky130_1k/:
bash scripts/run_v104_macro_probe.sh > macro_probe.log 2>&1
rc=$?; tail -n 60 macro_probe.log; echo EXIT_CODE=$rc
```

`config/config_hard_sram.mk` bật macro trong full ASIC qua ORFS `VERILOG_DEFINES` và `ADDITIONAL_{LEFS,LIBS,GDS}`; `config/config_macro_probe.mk` tổng hợp một macro để kiểm tra **tích hợp thư viện**. Cả hai không phải full ASIC PnR. Không có script chạy full-chip place/route ở V1.04 vì lượng RAM còn lại chưa được ánh xạ.

Các điều kiện bổ sung trước tapeout: pad/IO chính thức, nguồn cấp và hook PDN macro, macro floorplan có keep-out, đúng mô hình behavioral + timing, công nghệ Sky130 đúng corner, IR/EM, STA, DRC, LVS, GDS stream-out, functional equivalence full HandSeg + CNN và giao tiếp memory controller thật. Cổng mem_* hiện tại vẫn là 64-bit transaction, không phải SDRAM PHY JEDEC.

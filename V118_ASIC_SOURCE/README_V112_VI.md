# ASIC V1.12 – Functional integration: residual_word_engine + SRAM thật

## Mục tiêu và phạm vi

V1.11 mới xác nhận hierarchy AI; V1.12 kiểm thử **RTL `residual_word_engine` gốc** tương tác qua **API `reference_feature_memory` gốc** với 2 backend riêng:
- Golden: V1.06 inferred feature RAM (`BANK0_INIT_FILE=""`).
- Hard: V1.09 single-copy SRAM `sky130_sram_2kbyte_1rw1r_32x512_8` dùng **Verilog model chính thức đã tải từ VLSIDA**.

Cả hai chạy cùng một bài test: nạp bank0 và bank1 qua cổng write, engine thực hiện residual 8 lane mỗi 64-bit word, ghi bank2, rồi đọc lại bank2. Công thức oracle độc lập `min(main_byte + shortcut_byte,255)` với multiplier=1, zero-point=0, shift=0. Kiểm tra mọi write trên interface, số word, bank/address, checksum dữ liệu, stall write ngẫu nhiên xác định trước, rồi so trace hai backend. Không sửa RTL đang dùng, không dùng SRAM fake, không thay weights của CNN.

## Cài đặt và chạy

Giải nén **trực tiếp vào root** của project V1.07 đã được patch tới V1.11:

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V112_RESIDUAL_INTEGRATION_PATCH.zip .
bash scripts/run_v112_residual_integration.sh smoke
```

Nếu smoke PASS, chạy thêm test stress qua biên tile 511→512:

```bash
bash scripts/run_v112_residual_integration.sh stress
```

Nếu lỗi, xem `output/v112_residual/{golden,hard}_{compile,}.log` và gửi các dòng lỗi. Test không chạy Docker, không chạy PnR, không tái xuất GDSII.

## Điều kiện PASS

- `PASS tb_v112_residual_memory WORDS=4 WRITES=4 ... READBACK=OK` (golden, hard).
- `[PASS] V112 residual engine integrated with V109 hard-SRAM and V106 reference: 4 writes ...`.
- `stress`: 513 words, bắt qua địa chỉ word 511/512, có write backpressure, tất cả 513 writes phải khớp oracle.

## Giới hạn quan trọng

- Chỉ kiểm thử **một engine residual**, không thể coi là HandSeg full inference 65 layer hoặc cả CNN.
- Chỉ instantiate 8 bank x 1024 word trong test thay vì nguyên dung lượng 8 bank; kiểm tra đầy đủ capacity đã có ở V1.10.
- Không xử lý vấn đề DRC bên trong macro hoặc signoff.
- Nếu test fail ở dữ liệu/thời gian, phải điều tra nguyên nhân, không bỏ qua assertion hay thay engine bằng mock.

# ASIC V1.17 — Near-full HandSeg + ROI + CNN compute-only GDS trial

## Tính chất

Đây là **lần thử tạo GDSII từ top `asic_ai_top` thật**, giữ toán tử tính toán, FSM/handshake và pipeline HandSeg, crop/resize ROI, MobileNet CNN 7 block và classifier. KHÔNG phải residual-only và KHÔNG phải chip AI hoàn chỉnh hoạt động. Gói **chỉ** gồm patch để áp dụng vào thư mục V1.07 đã được cài V1.16 + Liberty Bus Fix.

**Bộ nhớ thiếu là giả về mặt hình học, không có dữ liệu, transistor hay tính năng lưu trữ.** Không thể chạy inference và tuyệt đối không đưa GDSII này đi chế tạo. Không coi đây là DRC/LVS/STA signoff. Không thay SRAM gốc hoặc weight hex.

## Thay đổi thực tế so với V1.16

- Ngoài 2 giao diện macro không chức năng của V1.16 (CNN weight ROM 96-bit; FIFO pixel 24-bit), V1.17 **trừu tượng hóa đúng payload RAM** trong 2 loại module CNN nặng:
  - `stream_row_buffer_3x3_parallel_hwc_stage2_banks3/banks4`: 9/12 mảng RAM mỗi module. Bảo toàn logic tính địa chỉ/chọn kênh, row tag, trạng thái và ma trận 3×3; thay payload bằng macro trống `v117_MISSING_ROW_RAM` (8 bit, địa chỉ 16 bit).
  - `top_residual_vector_store_row4_streaming`: RAM vector packed, có cấu hình 192/256/512/1024 bit. Bảo toàn kiểm soát hàng, pack vector, địa chỉ và handshake; thay payload bằng macro trống tương ứng.
- Các MAC, convolution, phép toán residual, concat, GAP, FC, preprocess, ROI và CNN vẫn là source gốc. Những RAM khác *có thể* vẫn được map thành standard-cell nếu Yosys không nhận macro; xem báo cáo.
- Cấu hình floorplan: 20 mm × 20 mm, chỉ để chứng minh flow; không có cơ sở foundry signoff. Tài nguyên Docker giới hạn 6 GiB/mỗi stage, timeout 20 phút/giai đoạn nhằm tránh treo vô hạn.
- Mọi output V1.09–V1.16 và original RTL được giữ nguyên; output mới nằm ở `output/v117_nearfull/`.

## Chạy một lệnh trong Ubuntu WSL

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V117_NEARFULL_GDS_PATCH.zip .
bash scripts/run_v117_nearfull_gds.sh gds
```

Điều kiện: Docker Engine hoạt động; `openroad/orfs:latest`, sv2v, 1KiB SRAM LEF/GDS/Liberty đã cài sẵn theo V1.09–V1.16. Nếu thiếu, script báo lỗi ngay, không đưa ra kết quả giả.

## Kết quả thật sau khi chạy

- Nếu **đến hết ORFS `finish`**: `output/v117_nearfull/results/6_final.gds` (GDS compute+nonfunctional placeholders) và `6_final.gds.sha256`.
- Dù thất bại: `output/v117_nearfull/BAO_CAO_V117.md`, `status.txt`, `synth.log`, `floorplan.log`, `finish.log` nếu giai đoạn đó đã chạy.
- `inspect.log` đếm số SRAM 1KiB thật và số macro bộ nhớ chưa chức năng trong netlist; không bao giờ coi mere source declarations là physical PASS.

Nếu cần GDS báo cáo và giai đoạn bị lỗi, cung cấp cuối log của giai đoạn lỗi. Đừng chạy lại các test V1.09–V1.13.

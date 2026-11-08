# ASIC V1.08 – Chuyển tile 4 SRAM từ OpenDB sang floorplan và thử GDSII

**Điểm xuất phát đã xác nhận trên WSL:** V1.07 `run_v107_unit_tests.sh` PASS (sau bản vá hold), và `run_v107_macro_odb_probe.sh` xác nhận `SRAM_MACRO_COUNT=4`.

**Phạm vi:** 1 tile RAM HandSeg 64-bit × 512 word với bốn hard SRAM 2 KiB SKY130; hoàn toàn không thay RTL/thuật toán AI. Bản vá **chỉ bổ sung** config và scripts. Nó không làm cho 2.256 macro của chip tổng khả thi để đặt/chế tạo.

## Hướng dẫn cài bản vá vào V1.07 trên WSL

Tải `AI_ASIC_V108_4MACRO_TILE_PHYSICAL_PATCH.zip` về Windows Downloads rồi chạy:

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V108_4MACRO_TILE_PHYSICAL_PATCH.zip .
bash scripts/run_v108_tile_physical.sh floorplan
```

Script sử dụng Docker `openroad/orfs:latest`, `make floorplan`, bố trí 4 macro tọa độ cố định theo lưới 2×2, nối pin nguồn `vccd1/vssd1` vào `VDD/VSS` của sky130hd rồi đọc checkpoint `2_2_floorplan_macro.odb` để kiểm tra đủ 4 macro, status đã đặt, bbox không chồng lên nhau hay vượt lõi.

Khi floorplan PASS:

```bash
bash scripts/run_v108_tile_physical.sh gds
```

Script chạy `make finish` (bao gồm placement/routing/finishing theo ORFS), chỉ báo thành công nếu có `output/v108_4macro/results/6_final.gds` không rỗng. **Nếu bước nào lỗi:** in 55 dòng cuối `<stage>.log`, không tự sửa RTL. Đính kèm `output/v108_4macro/{floorplan,finish,verify_placement}.log` để debug.

## Giới hạn quan trọng

- Floorplan PASS không có nghĩa là timing/DRC/LVS PASS; `6_final.gds` nếu xuất được vẫn là tile, không phải AI chip hoàn chỉnh.
- Cần kiểm tra tiếp kết nối nguồn, STA, DRC và LVS trên GDS thật trước khi dùng để chế tạo.
- V1.07 tổng có 2256 macro feature HandSeg (~642 mm² diện tích footprint); **không** chạy full-chip PnR trước khi giải quyết diện tích và các ROM/RAM còn lại.
- File vá tạo và kiểm tra cú pháp tĩnh ở môi trường hiện tại; chưa kiểm tra thực thi Docker ORFS của người dùng. Kết quả trên WSL mới là bằng chứng thực nghiệm.

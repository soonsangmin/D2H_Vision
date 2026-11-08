# V1.16 — Sửa lỗi cổng RDATA trong Liberty placeholder

Log người dùng:

```
ERROR: Module `v116_MISSING_PIXEL_FIFO_RAM' ...
does not have a port named 'RDATA'.
```

## Nguyên nhân

Script cũ tạo Liberty với `pin("RDATA[0]")`, `pin("RDATA[1]")`...
thay vì `bus (RDATA) { bus_type : v116_bus24; pin (RDATA[23:0]) { } }`.
Khi `read_liberty` thiết lập blackbox trong Yosys, các pin scalar đơn lẻ
không phải vector port `RDATA` mà Verilog dùng. Lỗi xảy ra ở hierarchy,
chưa tới synthesis hoặc GDS.

## Phạm vi thay đổi

Chỉ file `scripts/v116_generate_views.py`. GDS/LEF placeholder không thay đổi
kích thước hay vị trí pin; `.lib` tạo lại với bus đúng chuẩn cho ROM và FIFO:
ADDR, DATA, WADDR, WDATA, RADDR, RDATA.

**Lưu ý:** các macro V1.16 chỉ là placeholder phi chức năng, không lưu trữ dữ liệu.
Kết quả GDS nếu xuất được không thể chạy inference và không đủ điều kiện tapeout.

## Cách áp dụng

```
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V116_LIBERTY_BUS_FIX.zip .
python3 scripts/v116_generate_views.py
bash scripts/run_v116_nearfull_gds.sh gds
```

Bản vá được kiểm tra cú pháp Python và self-check file .lib sinh ra ở môi trường
chuẩn bị, **chưa được chạy trên ORFS của máy người dùng**.

Nếu ORFS thất bại, gửi 50 dòng cuối của:
`output/v116_nearfull/synth.log` (hoặc `floorplan.log`, `finish.log`).

# V1.02a — Testbench Backpressure & Screening Serial Build

## Thay đổi
- `tests/tb_rgb96_classifier.sv`: thay backpressure dựa trên `accepted` (deadlock tại accepted=3) bằng counter theo clock 0..6. Không đụng đến module CNN thật.
- `scripts/run_screening_only.sh`: `make -j2` thành `make -j1` nhằm giảm nguy cơ race/JSON bị ghi dở trong `mem_dump.py` (giả thuyết cần xác nhận trên máy thực).

## Kiểm tra
```bash
python3 scripts/verify_v102_static.py
bash scripts/run_unit_tests.sh
# Chỉ sau khi unit test PASS, nếu muốn kiểm tra screening:
bash scripts/run_screening_only.sh
```

## Lưu ý
- Bộ tạo gói không có `iverilog` hay Docker, nên chưa thể chứng nhận RTL simulation / ORFS PASS.
- Warning Icarus `constant selects in always_*` không phải nguyên nhân testbench bị treo.
- Screening thu nhỏ memory; không dùng netlist cho tapeout.
- Kiến trúc bộ nhớ chưa đầy đủ, chưa có GDSII thật.

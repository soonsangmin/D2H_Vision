# ASIC V1.07 — vá hold dữ liệu khi downstream backpressure

## Lỗi đã quan sát

`bash scripts/run_v107_unit_tests.sh` dừng tại `tests/tb_v107_feature_macro.sv:117`: `backpressure did not retain data`.

Nguồn `sky130_sram_2kbyte_1rw1r_32x512_8.v` của OpenRAM đặt `dout1 = X` sau cạnh clock dương (`T_HOLD`), rồi chỉ trả dữ liệu ở cạnh clock âm nếu có read. V1.07 trước đó nối output response trực tiếp với `bank_d0/1[sel]`, dù `rsp_valid` được giữ khi `rsp_ready=0`.

## Sửa ở đâu

Chỉ sửa `rtl/memory/v107_handseg_feature_memory_macro.sv`:

- Mỗi cổng đọc có `hold?_r` và `hold?_data_r`.
- Khi response chưa được nhận (`rsp_valid && !rsp_ready`), lấy mẫu dữ liệu SRAM **ở cạnh clock đầu tiên khi bị stall**, trước lúc macro model invalidates `dout1`.
- Giữ dữ liệu đã lấy mẫu đến khi consumer nhận response. Khi slot được phép đổi sang lệnh đọc mới, xóa cờ hold để chọn data macro tương ứng.
- Không đổi FSM CNN/HandSeg, không đổi địa chỉ bank, không đổi số 2.256 macro, không đổi testbench, không dùng dữ liệu giả.

## Cài vào dự án hiện tại WSL

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
cp rtl/memory/v107_handseg_feature_memory_macro.sv rtl/memory/v107_handseg_feature_memory_macro.sv.before_hold_fix
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V107_BACKPRESSURE_HOLD_PATCH.zip .
bash scripts/run_v107_unit_tests.sh > output/v107_hold_regression.log 2>&1
rc=$?
tail -n 35 output/v107_hold_regression.log
echo "EXIT_CODE=$rc"
```

**Chưa có bằng chứng PASS Icarus từ người dùng.** Kiểm tra RTL này trên WSL trước khi tiếp tục. Các model macro giữ clock-to-Q theo OpenRAM; timing, signoff, GDS chưa được kiểm tra.

Nếu `EXIT_CODE` khác 0, gửi 40 dòng cuối log; không chạy lại bước tải macro hoặc synth toàn chip.

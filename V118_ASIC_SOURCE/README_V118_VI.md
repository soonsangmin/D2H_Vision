# V1.18 — Nỗ lực GDSII gần đầy đủ, ABC Mapping tối giản

Áp dụng **trên thư mục V1.07 có các bản vá V1.16/V1.17**, không chép đè RTL.

## Chạy

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V118_FAST_ABC_PATCH.zip .
python3 scripts/v118_apply_fast_abc.py
bash scripts/run_v117_nearfull_gds.sh gds
```

- Giữ nguyên `asic_ai_top`, 61 source module, tính toán HandSeg, ROI, CNN.
- Giữ nguyên memory placeholder **không có chức năng** V1.16/V1.17.
- Thay `ABC_SCRIPT` thành `strash; map`, bỏ nhiều vòng &nf/&syn2 của `abc_speed.script`.
- Không dùng mock/shrink RAM. Không thay đổi hành vi RTL nguyên bản.
- Giới hạn thời gian: synth 2400 giây, floorplan 900 giây, finish 1800 giây.
- GDS mục tiêu: `output/v117_nearfull/results/6_final.gds`.
- Báo cáo tự sinh: `output/v117_nearfull/BAO_CAO_V117.md`.

## Giới hạn

Chưa kiểm nghiệm ABC/ORFS end-to-end trong Docker của bạn. `strash; map` có thể nhanh hơn, nhưng nếu thời gian chủ yếu nằm ở **trích xuất BLIF** trước ABC mapping, vẫn có thể timeout. Dùng `exit=124/137` và log cuối để phân biệt. **Không tuyên bố thành công nếu GDS chưa tồn tại.** Ngay cả khi có, đây chỉ là physical compute trial với bộ nhớ không chức năng, không đạt signoff hoặc tapeout.

Nếu cần khôi phục cấu hình ban đầu, dùng file `.pre_v118` của cấu hình và runner do script tự sao lưu.

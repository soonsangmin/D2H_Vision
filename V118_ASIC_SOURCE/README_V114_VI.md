# V1.14 — CHẠY TRỰC TIẾP FULL-CHIP GDSII (thử nghiệm kỹ thuật)

## Mục tiêu

Dừng test theo engine. Chạy MỘT LẦN toàn bộ `asic_ai_onchip_top` gồm HandSeg + ROI + CNN theo 3 checkpoint Yosys synthesis → floorplan → ORFS finish (placement, CTS, routing, GDS streamout). Chỉ chạy trên source đầy đủ, KHÔNG mock RAM, KHÔNG bỏ trọng số. Không lấy GDSII của tile V1.09 thay cho full-chip.

## Đầu vào và giới hạn

Đã xác minh từ các run WSL trước:
- V1.09: tile 2x2KiB SRAM có GDSII vật lý, DRC/LVS/STA chưa signed off.
- V1.10: subsystem HandSeg 8 bank có 1.128 SRAM 2KiB trong OpenDB.
- V1.11 FAST: cây instance từ top AI có 1.128 SRAM 2KiB + 52 SRAM 1KiB.
- V1.12: residual functional smoke/stress PASS.

**Chưa có** full-chip synthesis, placement, routing, GDSII. Các bộ nhớ snapshot, ROI và ROM trọng số vẫn là RTL inferred memories: `SYNTH_MOCK_LARGE_MEMORIES=0` sẽ buộc synthesis tìm logic thật; có nguy cơ vượt khả năng 8GiB RAM WSL. Bản script KHÔNG bảo đảm sẽ tạo được GDSII nếu tổng hợp không đủ RAM hoặc macro chưa kết nối được.

Diện tích die cho thử nghiệm 30,000 x 30,000 um (900 mm²). Không phải kích thước đã xác nhận cho reticle của bất kỳ foundry nào. Bản GDSII nếu tạo thành công vẫn chưa tapeout-ready vì DRC, LVS, STA và padframe chưa signoff; SRAM OpenRAM đã có lỗi DRC trong lần kiểm tra V1.08.

## Hướng dẫn WSL

Giải nén patch tại root dự án V1.07 đã cài V1.09/V1.10/V1.11:

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V114_FULLCHIP_GDS_ATTEMPT_PATCH.zip .
bash scripts/run_v114_full_chip_gds.sh
```

Script tự chuẩn bị toàn bộ 68 source RTL qua sv2v đã cài V1.11, kiểm tra đủ 6 view LEF/Liberty/GDS của 2 macro SRAM, rồi làm lần lượt synth / floorplan / finish. Output giữ riêng trong `output/v114_fullchip`. Có dòng tiến độ mỗi ~30s. Không chạy các test V1.09-V1.13.

## Các kết quả

- `output/v114_fullchip/BAO_CAO_V114.md` luôn được tạo, kể cả nếu full-chip bị lỗi.
- `output/v114_fullchip/synth.log`, `floorplan.log`, `finish.log` cho từng bước.
- `output/v114_fullchip/inspect.log` xác minh 1.128 x SRAM2KiB và 52 x SRAM1KiB **sau synthesis**, khác hẳn V1.11 chỉ hierarchy.
- `output/v114_fullchip/results/6_final.gds` CHỈ khi ORFS finish thành công; không giả mạo hay lấy tile GDS.

## Khi bị lỗi

Không chạy DRC hay test engine nữa. Gửi **cuối file log của stage FAIL** và `BAO_CAO_V114.md` để xử lý đúng một blocker trên đường full-chip GDS:

```bash
tail -n 60 output/v114_fullchip/synth.log
# hoặc floorplan.log / finish.log tùy trạng thái
cat output/v114_fullchip/BAO_CAO_V114.md
```

Nếu Yosys bị OOM ở bước synth do ROM/feature còn inferred, cần có lựa chọn kỹ thuật thật: máy nhiều RAM hơn, hoặc thiết kế macro/ROM có physical layout. Không được chuyển inferred memories sang zero / blackbox không có GDS để 'ép ra' file.

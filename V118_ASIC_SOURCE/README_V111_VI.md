# ASIC V1.11 — Xác minh kết nối 1.128 hard-SRAM tới top AI thật

**Điểm xuất phát:** V1.10 đã xác nhận 1.128 SRAM macro trong OpenDB của *memory subsystem*. Đây không phải kết quả của `asic_ai_onchip_top`.

## Mục tiêu

V1.11 không thay đổi RTL và không gọi lại V1.09/V1.10. Chạy **read_slang + hierarchy** trên `asic_ai_onchip_top` gốc, với `V107_HARD_FEATURE_SRAM`, `V109_SINGLE_COPY_SRAM` và `ASIC_USE_SKY130_SRAM`. Sau đó duyệt cây module thực sự có thể đi đến từ top và đếm **instance** SRAM 2 KiB, không đếm module definition mồ côi. Kiểm tra trực tiếp 8 bank trong hierarchy, không dùng `memory_map`, `synth`, `abc` hoặc PnR.

Chuỗi kết nối đã kiểm chứng bằng đọc source: `asic_ai_onchip_top.u_ai` → `asic_ai_local_core.u_detector` → `handseg_camera_system.u_handseg` → `handseg_live_top.g_reference_mem.u_mem` → `reference_feature_memory.g_v107_physical.u_physical` → 8 bank V1.09. Bộ CNN vẫn nằm trong `asic_ai_local_core.u_classifier`.

## Cài đặt và chạy (WSL)

Điều kiện: V1.09/V1.10 đã cài, gói `AI_ASIC_V111_AI_TOP_HIERARCHY_PATCH.zip` ở Downloads.

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V111_AI_TOP_HIERARCHY_PATCH.zip .
bash scripts/run_v111_ai_hierarchy.sh
```

Kết quả mong đợi **nếu RTL được elaboration đúng**:

```text
V111_TOP=asic_ai_onchip_top
V111_2K_SRAM_COUNT=1128
V111_HANDSEG_BANK_COUNTS=480 240 180 20 6 2 180 20
[PASS] 1128 HandSeg physical SRAM instances reachable from REAL AI top
```

Dòng `V111_1K_CNN_SRAM_COUNT` cho biết SRAM 1 KiB của CNN trong hierarchy trước synthesis, **không** chứng minh chúng sẽ tồn tại trong netlist cuối.

Nếu thất bại, gửi **chỉ 60 dòng cuối** của `output/v111_ai_top_hierarchy/elaboration.log` (không cần chạy lại regression). File `ai_top_hierarchy.json` có thể rất lớn, không cần tải lên nếu chưa được yêu cầu.

## Phạm vi và vấn đề chưa giải quyết

- Đây là **elaboration**, không phải synthesis toàn chip/OpenDB. Đặc biệt kết quả PASS **không** loại trừ việc Yosys fine-synthesis sau đó xóa một phần memory/data path (vấn đề V1.04).
- Không so sánh inference HandSeg/CNN với FPGA V6.23. Không chứng minh latency/throughput của backpressure tới toàn bộ 65 layer.
- `parameter_store_v141` hiện vẫn khai báo 122.478 word ×64-bit trọng số và 1.261 nhóm lượng tử gồm 904-bit/nhóm (~1,07 MiB) dưới dạng inferred/initialized memories, **chưa có macro vật lý/ROM đã xác minh**.
- `asic_onchip_frame_memory` vẫn có 600 KiB snapshot RGB565 và 18 KiB RGB96 inferred RAM; các RAM CNN còn lại cũng chưa được ánh xạ đầy đủ.
- SRAM 2 KiB bản gốc vẫn chưa có DRC signoff; macro-only HandSeg khoảng 321 mm² trước các khối khác.
- Không được gọi đây là GDSII AI hoàn chỉnh, DRC/LVS/STA PASS, hay thiết kế tapeout-ready.

Sau khi check hierarchy PASS, ưu tiên kế tiếp là **functional regression HandSeg thật với SRAM 2R1W** so với reference, rồi xử lý trọng số và các RAM còn lại trước khi thử full-chip PnR.

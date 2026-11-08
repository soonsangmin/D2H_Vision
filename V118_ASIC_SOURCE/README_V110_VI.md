# ASIC V1.10 — HandSeg 8-bank physical SRAM integration probe

**Goal:** Validate that ALL 1,128 hard SRAM macro instances survive Yosys **and** appear in the OpenDB of the 8-bank HandSeg feature-memory subsystem. Previous V1.09 tests only proved **2 macros in one tile**. This patch keeps V1.07/08/09 RTL and GDS files unchanged; it adds a dedicated synthesizable subsystem top, ORFS configuration, and result audit.

**Important distinctions:** This is not the `asic_ai_onchip_top`, not HandSeg+CNN inference, and not physical placement. It does not run timing, LVS, DRC, PnR, or produce GDS. Do not claim tapeout readiness from a pass.

## Install and execute (WSL)

Prereqs: V1.09 patch already installed and tests PASS, original OpenRAM SRAM `.lef` and `.lib` already downloaded. Extract this archive into the existing **V1.07 project root**:

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V110_FULL_HANDSEG_SRAM_ODB_PROBE_PATCH.zip .
# Optional fast check before synthesis:
python3 scripts/v110_preflight.py
# Full memory-subsystem synthesis and real OpenDB count:
bash scripts/run_v110_8bank_odb_probe.sh
```

Expected AFTER synthesis succeeds:

```text
V110_SRAM_MACRO_COUNT=1128
V110_BANK_MACRO_COUNTS=480 240 180 20 6 2 180 20
PASS: Full 8-bank HandSeg feature memory = 1128 physical SRAM macros in top OpenDB
```

These strings are targets, not results verified on the user's WSL. A log at `output/v110_handseg_8bank/build.log` is retained. This synthesis is much larger than the 2-macro tile and **may require significant time and RAM**. It is intentionally not launched as full-chip PnR. The log captures the first actual ORFS scaling constraint.

## Independent source facts

- Logical 64-bit bank depths: [122880,61440,46080,5120,1280,384,46080,5120]. Each tile holds 512 words (64-bit) and maps to **2 × 32-bit × 512** physical SRAM.
- Tile counts: [240,120,90,10,3,1,90,10] => 564 tiles. Physical SRAM counts: [480,240,180,20,6,2,180,20] => **1,128 macros**.
- The source requires `V107_HARD_FEATURE_SRAM` **and** `V109_SINGLE_COPY_SRAM`. `BANK0_INIT_FILE("")` activates the hard-SRAM path in `reference_feature_memory`.
- The wrapper preserves V1.09 read0/write port arbitration. The upstream HandSeg compute pipeline still needs end-to-end inference verification; no full-function equivalence is implied.
- Macro-only footprint from the LEF is approximately 321 mm²; 1,128 instances plus logic, routing, power and pads will require more. This may exceed practical SKY130 manufacturing/tapeout constraints. SRAM macro itself has unresolved DRC differences; do not waive them without foundry acceptance.

## Failure handling

If script fails, post the following (no need to rerun V1.09):

```bash
tail -n 60 output/v110_handseg_8bank/build.log
cat output/v110_handseg_8bank/macro_count.log 2>/dev/null || true
```

**Next true milestone after this probe:** full HandSeg inference RTL with actual SRAM + weight ROM vs V6.23 reference, then CNN memory macro mapping and top-level physical feasibility. No memory shrinking or dummy AI outputs.

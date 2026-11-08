# ASIC V1.09 — 2-macro HandSeg SRAM tile (single-copy 1RW+1R)

## What actually changes

This is an **OPTIONAL RTL EXPERIMENT** on top of the tested V1.07+hold patch. It does **not** overwrite V1.07 memory bank RTL or the V1.08 physical results. The `V109_SINGLE_COPY_SRAM` compile definition selects the new module.

- V1.07: one 64-bit x 512 tile = 4 x 2KiB SRAM (two full 1RW+1R copies).
- V1.09: same 64-bit x 512 tile = **2 x 2KiB SRAM**, using `dout0` from RW port0 for read0 and `dout1` from R port1 for read1.
- A write to the **same 512-word tile** as read0 stalls (`wr_ready_o=0`) because both need physical port0, even if addresses differ. Concurrent write/read1 of different addresses is allowed via port0+port1. Same-word collision with either read port stalls the write. Reads are accepted first and require ready/valid compliance by the upstream write engine.
- RAM contents and arithmetic are NOT approximated or mocked; parameters/weights are NOT moved out of chip. Full AI is still not integrated as a physically realizable chip.
- Original OpenRAM Verilog model invalidates port0 Q around clock edges just as it does port1. V1.09 inherits V1.07 **backpressure hold fix**, and includes a fresh test.

## Physical savings

564 tiles: **2,256 -> 1,128 SRAM hard macros**, **~641.9 -> ~321.0 mm²** macro footprint (using LEF 683.1 x 416.54 microns). This is not complete die area; it is still extremely large and has no signoff. Even if tests pass, the macro source *itself* has nonzero DRC and needs qualified signoff. No DRC waiver is authorized by this patch.

## Installation on your current V1.07 folder

Prerequisite: the V1.07 backpressure hold fix has already been applied, and SRAM Verilog/LEF/Liberty/GDS downloaded.

```bash
cd ~/asic_projects/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
python3 -m zipfile -e \
  /mnt/c/Users/tienh/Downloads/AI_ASIC_V109_DUALPORT_SINGLECOPY_PATCH.zip .
bash scripts/run_v109_unit_tests.sh
```

If the test says PASS, then, without running full-chip synthesis:

```bash
bash scripts/run_v109_macro_odb_probe.sh
```

If OpenDB count reaches 2, run the full **2-macro tile GDS** (still not full AI):

```bash
bash scripts/run_v109_physical.sh gds
```

Expected macro count from the **new** 64-bit physical tile is `V109_SRAM_MACRO_COUNT=2` in `output/v109_2macro/results/1_synth.odb`. Do not confuse this with the old V1.08 four-macro tile. The 2-macro tile GDS, if built, is at `output/v109_2macro/results/6_final.gds`. DRC/LVS are NOT assumed clean (macro is known to have violations). Simulation is a required gate; don't proceed on a failing test.

## Production blockers (unchanged)

1. OpenRAM macro is not clean under the earlier KLayout generic SKY130 rule deck (154,466 V1.08 markers were inside macro hierarchy); upstream Magic DRC log also reports 32 errors per macro. **Do not waive these without a foundry-approved deck and a qualified macro release.**
2. 1.09 read0/write port contention causes new stalls. All producers must honor write `ready`; verify HandSeg pipeline end-to-end and performance before calling this functionally equivalent to V1.06.
3. Snapshot, full CNN line buffers/weights, HandSeg weight initialization, area planning, routing, STA, LVS are not complete. No full-chip GDSII exists.
4. 1RW+1R `dout0`/`dout1` are modeled at the macro's falling edge with delay; timing must be validated for half-cycle paths.

## Rollback

V1.07 remains unchanged unless the new define is explicitly enabled; simply omit `-D V109_SINGLE_COPY_SRAM`, or keep using the existing V1.07/V1.08 scripts. This patch does not alter the original macro GDS/LEF/Liberty or existing GDS results.

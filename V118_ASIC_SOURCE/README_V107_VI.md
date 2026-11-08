# AI ASIC V1.07 — HandSeg 64-bit 2R1W physical SRAM integration (experimental)

## Scope
This is a **real macro-aware RTL branch** continuing V1.06. The default reference implementation remains available and all prior tests should still run. The optional `-D V107_HARD_FEATURE_SRAM` switch uses the mirrored `sky130_sram_2kbyte_1rw1r_32x512_8` macro for the **HandSeg feature banks only**. CNN FIFO and all other memories are NOT remapped by this release. This is not GDSII.

The original `reference_feature_memory` module and the camera-to-AI top's interfaces are kept. In live top `BANK0_INIT_FILE("")` selects physical SRAM when enabled; `handseg_reference_top` with a non-empty BANK0_INIT_FILE remains reference RAM for golden simulation. The full reference path remains V1.06 with no define.

## Architecture
- 8 logical 64-bit banks: 122880, 61440, 46080, 5120, 1280, 384, 46080, 5120 words.
- Split each bank into 512-word physical tiles. Each tile is 64-bit = two 32-bit macro lanes, mirrored for independently simultaneous read0 and read1. Thus **4 physical SRAMs per tile**.
- 564 tiles => **2256 x 2KiB macro instances**. 2.200 MiB of unique logical feature data occupies ~4.406 MiB of physical macro storage because of read-port replication and rounding.
- Both mirrored copies always receive each accepted 64-bit write.
- `rd*_rsp_valid_o` asserts after the request clock edge, and `dout1` from the macro becomes valid after macro clock-to-Q. The upstream OpenRAM Verilog model implements reads at the **falling edge** with a delay; downstream accepts the result at the **next rising edge**. Timing STA must prove this half-cycle budget at the final target frequency.
- Read/write same bank and word at the same cycle is **not allowed** in the physical macro. `wr_ready_o` deasserts to serialize writes; read retains priority. This differs from V1.06's same-edge old-data `bank_write` NBA semantics and changes write acceptance timing. Engine ready/valid integration and a real CNN+HandSeg end-to-end regression are required before claiming equivalence. A writer must maintain `valid`, address and data while `ready=0`.
- MACRO SRAM IS VOLATILE and cannot be pre-initialized with a `$readmemh` in GDS. This branch does not claim to have physically implemented weights/parameter ROM or preloaded image contents.

## SRAM geometry and realistic die size
Based on upstream official 2KiB LEF dimensions 683.1 × 416.54 µm:
- 2256 macro footprints * 0.284525 mm² = **~641.9 mm² macro-only**, before all place/route spacing, blockages, supply, ESD, pad ring, snapshot, weights and CNN logic. This is not a proven tapeout-sized design. A custom larger SRAM macro, a genuine multiported macro, a change in access scheduling, or multiple dies may be necessary to fit fabrication constraints.
- Upstream source: https://github.com/VLSIDA/sky130_sram_macros/tree/main/sky130_sram_2kbyte_1rw1r_32x512_8 (Apache-2.0).
- Physical source pin view is 1RW+1R, NOT true native 2R+1W. Here two identical 1RW+1R copies are used.

## On WSL Ubuntu
```bash
cd ~/asic_projects
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W.zip .
cd AI_ASIC_V107_HANDSEG_PHYSICAL_SRAM_2R1W
bash scripts/v107_fetch_macro_views.sh
bash scripts/run_v107_unit_tests.sh
```

For full on-chip source configuration `config/config_onchip_v107_hard_feature.mk` adds real SRAM LEF/Liberty/GDS and `-D V107_HARD_FEATURE_SRAM` with memory mocking **off**. **DO NOT RUN full chip synthesis** until the other many megabits of memories are mapped; otherwise Yosys can exhaust compute resources producing flop arrays.

## Verification limits and next steps
1. Static geometry count and scripted HDL test require independent WSL execution; this package was created without iverilog.
2. 2R+1W collision semantics are altered by backpressure, tested at interface but not yet full-engine equivalence.
3. Proper physical pin power/ground, LVS/DRC, macro characterization and floorplan are mandatory.
4. Weight ROM/boot mechanism, full CNN/HandSeg functionality and total die area still unresolved.
5. This is an intermediate **memory-subsystem milestone**, not finished ASIC.

## Optional OpenROAD 4-macro physical-link probe
After passing RTL simulation, `bash scripts/run_v107_macro_odb_probe.sh` builds the **actual V107 64-bit tile RTL** with four hard SRAMs and verifies `SRAM_MACRO_COUNT=4` in a real OpenDB. Unlike screening, this uses no RAM shrink. It is a tile-only probe, not a full chip GDS. The script requires Docker ORFS and previously downloaded macro views. Its log is stored at `output/v107_4macro/build.log`.

# V1.06 — HandSeg per-bank feature memory sizing (full-onchip RTL)

This release continues V1.05. It does not modify CNN/HandSeg computation or network weights. It **reduces allocation** of `reference_feature_memory.sv` from uniformly 131,072×64-bit×8 banks (8 MiB) to schedule-bounded bank sizes. All memories remain *inferred* RTL memories; no claim of hard-macro mapping, ASIC synthesis, STA or GDSII.

## Result (64-bit words)

| Bank | Required by static schedule | Allocated | KiB |
|---|---:|---:|---:|
| BANK_A | 122,880 | 122,880 | 960 |
| BANK_B | 61,440 | 61,440 | 480 |
| BANK_TEMP | 46,080 | 46,080 | 360 |
| BANK_SKIP80 | 5,120 | 5,120 | 40 |
| BANK_SKIP40 | 1,280 | 1,280 | 10 |
| BANK_SKIP20 | 320 | 384 | 3 |
| BANK_AUX | 46,080 | 46,080 | 360 |
| BANK_MASK | 5,120 | 5,120 | 40 |
| **Total** | **288,320** | **288,384** | **2,253** |

Memory savings in this block: 8 MiB -> 2.2002 MiB, ~72.5%. `BANK_AUX` must accommodate 80×64×9 (46,080 words) during the largest CONCAT. The previous rough estimate treating AUX as tiny was incorrect.

## How sizing was established

`scripts/v106_bank_depth_audit.py` reads 82 static schedule commands, 65 layer descriptors, 3 concat descriptors. For conv it uses `hin×win×in_groups8` source and `hout×wout×out_groups8` destination. Residual uses `word_count`; concat uses the configured input/output shapes; GAP, presence and ROI use hardcoded engine constants verified against RTL. The script also checks key engine address expressions and *fails closed* if the expected extents change. It emits `docs/V106_HANDSEG_BANK_CAPACITY.csv`.

On each cycle `reference_feature_memory.sv` serves 2 synchronous read ports + 1 write as before. Simulation-only guards raise `$fatal` on accepted out-of-bank access; they are excluded with `SYNTHESIS`. No silent wrapping or truncation is added. `DEPTH_WORDS > 0` is retained as a legacy override to force the old equal-depth banking for compatibility testing. **Static address extents are necessary, not sufficient for functional equivalence:** dynamic control, traffic contention, ROM initialization and sensor pixel paths still need end-to-end verification.

## Run

```bash
cd ~/asic_projects/AI_ASIC_V106_HANDSEG_BANK_SIZING
bash scripts/run_v106_unit_tests.sh
```

This executes V1.05 static audit, new geometry audit, new dual-read/single-write boundary protocol test and original V1.05 small frame RAM test. Icarus simulation must be run on WSL; this package was prepared in an environment without Icarus.

## Critical physical risks remaining

- 2R+1W concurrently per feature store is **not** satisfied by a single 1RW1R macro (which has one read/write port and one separate read port) under arbitrary simultaneous reads/writes. Need multi-pumping/replication/port scheduling and matching timing, not direct macro replacement.
- HandSeg weights and CNN ROM need a verified non-volatile implementation (or boot-time loading, which then requires interface/protocol). Weight ROMs are not SRAM initialization on silicon.
- All snapshot/ROI/line-buffer/residual/CNN SRAM, pad ring, power, STA, DRC/LVS and GDS still remain. RAM allocation alone does not produce a manufacturable die.
- Reference feature memory has uninitialized words, as before; legal operation requires writes before reads (except any explicitly loaded simulation golden input). This package does not assert full network equivalence.

## Suggested next engineering milestone

Use this capacity table as a memory architecture contract. Implement a multiported physical macro subsystem (not a giant flop array) and verify cycle-accurate transaction semantics against this RTL reference. Separately, implement ROM/boot strategy for weights, then full RTL regression and unmocked synthesis.

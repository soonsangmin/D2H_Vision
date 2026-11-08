#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/v110_preflight.py
for f in macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8{.lef,_TT_1p8V_25C.lib}; do
  if [[ ! -s "$f" ]]; then echo "[BLOCKED] Missing $f" >&2; exit 2; fi
done
if ! command -v docker >/dev/null; then echo '[BLOCKED] docker missing' >&2; exit 2; fi
out=output/v110_handseg_8bank
mkdir -p "$out"/{results,reports,logs,objects}
# This is an intentionally LARGER synthesis than a 2-SRAM tile.
# It does not start place/route or run the AI network. Preserve all output.
echo '[START] Yosys + OpenDB for ALL 1128 HandSeg feature SRAM macros.'
echo '[NOTE] This can require substantial RAM/CPU. No PnR/GDS is attempted.'
if ! docker run --rm --mount "type=bind,source=$PWD,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc \
  'set -euo pipefail; source /OpenROAD-flow-scripts/env.sh; \
   make -j1 synth DESIGN_CONFIG=/workspace/config/config_v110_handseg_8bank_sram_probe.mk \
   RESULTS_DIR=/workspace/output/v110_handseg_8bank/results \
   REPORTS_DIR=/workspace/output/v110_handseg_8bank/reports \
   LOG_DIR=/workspace/output/v110_handseg_8bank/logs \
   OBJECTS_DIR=/workspace/output/v110_handseg_8bank/objects' \
  > "$out/build.log" 2>&1; then
  echo '[FAIL] ORFS synth stage; last 60 lines:' >&2
  tail -n 60 "$out/build.log" >&2
  exit 3
fi
if [[ ! -s "$out/results/1_synth.odb" ]]; then
  echo '[FAIL] No OpenDB at expected path' >&2
  tail -n 40 "$out/build.log" >&2; exit 4
fi
# Count instances from the ACTUAL OpenDB (not Verilog declarations).
if ! docker run --rm --mount "type=bind,source=$PWD,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc \
  'set -euo pipefail; source /OpenROAD-flow-scripts/env.sh; \
   openroad -exit /workspace/scripts/v110_count_macros.tcl' \
  > "$out/macro_count.log" 2>&1; then
  cat "$out/macro_count.log" >&2
  exit 5
fi
cat "$out/macro_count.log"
echo '[PASS] V110 full HandSeg feature SRAM *subsystem* OpenDB verified.'
echo '[STOP] NOT integrated AI top; not placed/routed; NOT GDS; DRC/LVS/STA unverified.'

#!/usr/bin/env bash
# Usage: bash scripts/run_v109_physical.sh [floorplan|gds]
# Floorplan is default and stops safely before expensive route and final GDS.
set -euo pipefail
cd "$(dirname "$0")/.."
stage="${1:-floorplan}"
if [[ "$stage" != "floorplan" && "$stage" != "gds" ]]; then
  echo 'Usage: bash scripts/run_v109_physical.sh [floorplan|gds]' >&2; exit 2
fi
for f in macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8{.lef,_TT_1p8V_25C.lib,.gds}; do
  if [[ ! -s "$f" ]]; then
    echo "[BLOCKED] Missing hard macro view: $f. Run scripts/v107_fetch_macro_views.sh" >&2; exit 2
  fi
done
if ! test -s output/v109_tests/simulation.log || ! grep -q '^PASS tb_v109_feature_macro' output/v109_tests/simulation.log; then
  echo '[BLOCKED] First run: bash scripts/run_v109_unit_tests.sh (must PASS)' >&2
  exit 2
fi
out=output/v109_2macro
mkdir -p "$out"/{results,reports,logs,objects}
run_make() {
  local target="$1"
  docker run --rm --mount "type=bind,source=$PWD,target=/workspace" \
    --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc \
    "set -euo pipefail; source /OpenROAD-flow-scripts/env.sh; \
    make -j1 $target DESIGN_CONFIG=/workspace/config/config_v109_feature_2macro_physical.mk \
    RESULTS_DIR=/workspace/$out/results REPORTS_DIR=/workspace/$out/reports \
    LOG_DIR=/workspace/$out/logs OBJECTS_DIR=/workspace/$out/objects" \
    > "$out/${target}.log" 2>&1 || {
      echo "[FAIL] ORFS $target stage; last 55 lines:" >&2
      tail -n 55 "$out/${target}.log" >&2
      exit 3
    }
  echo "[OK] ORFS $target completed"
}
run_make floorplan
if [[ ! -s "$out/results/2_2_floorplan_macro.odb" ]]; then
  echo '[FAIL] Macro-placement checkpoint not produced' >&2; exit 3
fi
docker run --rm --mount "type=bind,source=$PWD,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc \
  'source /OpenROAD-flow-scripts/env.sh; openroad -exit /workspace/scripts/v109_check_2macro_placement.tcl' \
  > "$out/verify_placement.log" 2>&1 || {
    cat "$out/verify_placement.log" >&2; exit 4
  }
cat "$out/verify_placement.log"
if [[ "$stage" == "floorplan" ]]; then
  echo "[NEXT] For real tile routing+GDS: bash scripts/run_v109_physical.sh gds"
  exit 0
fi
run_make finish
if [[ ! -s "$out/results/6_final.gds" ]]; then
  echo '[FAIL] ORFS reported finish but 6_final.gds missing/empty' >&2; exit 5
fi
echo "[OK] TILE GDS generated: $out/results/6_final.gds"
echo '[NOTE] GDS is only 2-SRAM tile, NOT whole HandSeg/CNN chip. DRC/LVS/STA not signed off.'

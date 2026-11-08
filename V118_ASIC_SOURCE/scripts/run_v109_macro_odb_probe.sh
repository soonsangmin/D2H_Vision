#!/usr/bin/env bash
# OPTIONAL: verify the REAL V109 64b tile is linked to 2 SRAM macros in OpenDB.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_v109_single_copy.py >/dev/null
if ! test -s macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.lef; then
  echo '[BLOCKED] Download macro views first: bash scripts/v107_fetch_macro_views.sh'
  exit 2
fi
mkdir -p output/v109_2macro/{results,reports,logs,objects}
docker run --rm --mount "type=bind,source=$PWD,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc '
  set -euo pipefail
  source /OpenROAD-flow-scripts/env.sh
  make -j1 synth DESIGN_CONFIG=/workspace/config/config_v109_feature_2macro_probe.mk \
    RESULTS_DIR=/workspace/output/v109_2macro/results \
    REPORTS_DIR=/workspace/output/v109_2macro/reports \
    LOG_DIR=/workspace/output/v109_2macro/logs \
    OBJECTS_DIR=/workspace/output/v109_2macro/objects
' > output/v109_2macro/build.log 2>&1 || {
  tail -n 55 output/v109_2macro/build.log
  exit 3
}
cat > output/v109_2macro/count.tcl <<'TCL'
read_db /workspace/output/v109_2macro/results/1_synth.odb
set block [ord::get_db_block]
set n 0
foreach inst [$block getInsts] {
    if {[[$inst getMaster] getName] eq "sky130_sram_2kbyte_1rw1r_32x512_8"} {
        incr n
    }
}
puts "V109_SRAM_MACRO_COUNT=$n"
if {$n != 2} { error "Expected two V109 physical SRAMs" }
puts "PASS: 2 physical SRAM macros in V109 tile OpenDB (NOT AI chip)"
TCL
docker run --rm --mount "type=bind,source=$PWD,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc '
    set -euo pipefail
    source /OpenROAD-flow-scripts/env.sh
    openroad -exit /workspace/output/v109_2macro/count.tcl
  '

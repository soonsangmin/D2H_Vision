#!/usr/bin/env bash
# Attempt FULL AI physical GDS — no partial test, no memory mocks.
# Usage: bash scripts/run_v114_full_chip_gds.sh
set -euo pipefail
cd "$(dirname "$0")/.."
out=output/v114_fullchip
mkdir -p "$out"/{results,reports,logs,objects}
write_report() { python3 scripts/v114_report.py || true; }
trap write_report EXIT
printf '%s\n' 'STARTED' > "$out/status.txt"
echo '[V114] FULL AI CHIP: asic_ai_onchip_top, real SRAM macros, NO mocks'
for f in \
  macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.lef \
  macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib \
  macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.gds \
  macros/sky130_1k/sky130_sram_1kbyte_1rw1r_32x256_8.lef \
  macros/sky130_1k/sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib \
  macros/sky130_1k/sky130_sram_1kbyte_1rw1r_32x256_8.gds; do
  if [[ ! -s "$f" ]]; then
    echo "[FAIL] Hard SRAM physical view missing: $f" >&2
    echo 'FAILED_PREFLIGHT_MACRO_VIEW' > "$out/status.txt"
    exit 2
  fi
done
for f in scripts/v111_prepare_hierarchy.py scripts/v111_install_sv2v.py; do
  if [[ ! -s "$f" ]]; then
    echo "[FAIL] Missing prerequisite script: $f" >&2
    echo 'FAILED_PREFLIGHT_SOURCES' > "$out/status.txt"
    exit 2
  fi
done
python3 scripts/v111_prepare_hierarchy.py > "$out/sources.log"
sv2v_bin="$(python3 scripts/v111_install_sv2v.py)"
mapfile -t rtl_files < output/v111_ai_top_hierarchy/source_files.txt
printf '[V114] Converting %d source files (full AI)\n' "${#rtl_files[@]}"
if ! "$sv2v_bin" -D SYNTHESIS -D ASIC_USE_SKY130_SRAM \
    -D V107_HARD_FEATURE_SRAM -D V109_SINGLE_COPY_SRAM \
    "${rtl_files[@]}" > "$out/converted.tmp.v" 2> "$out/sv2v.log"; then
  tail -n 35 "$out/sv2v.log" >&2
  echo 'FAILED_SV2V' > "$out/status.txt"
  exit 3
fi
mv "$out/converted.tmp.v" "$out/converted.v"
if ! grep -qE '^[[:space:]]*module[[:space:]]+asic_ai_onchip_top\b' "$out/converted.v"; then
  echo '[FAIL] Converted Verilog missing AI top' >&2
  echo 'FAILED_SV2V_TOP' > "$out/status.txt"
  exit 3
fi

# One consistent log per stage; periodic live progress, no endless silent terminal.
after_make() {
  local stage="$1"
  local name="v114_${stage}_${$}"
  docker run --rm --name "$name" \
    --mount "type=bind,source=$PWD,target=/workspace" \
    --workdir /OpenROAD-flow-scripts/flow \
    openroad/orfs:latest bash -lc \
    "set -euo pipefail; source /OpenROAD-flow-scripts/env.sh; \
     ln -sfn /workspace/params ./params; ln -sfn /workspace/rtl ./rtl; \
     make -j1 '$stage' DESIGN_CONFIG=/workspace/config/config_v114_fullchip_gds.mk \
       RESULTS_DIR=/workspace/$out/results \
       REPORTS_DIR=/workspace/$out/reports \
       LOG_DIR=/workspace/$out/logs \
       OBJECTS_DIR=/workspace/$out/objects" \
    > "$out/$stage.log" 2>&1 &
  local docker_pid=$!
  # If the user Ctrl+C's the script, stop only the matching active container.
  trap 'docker rm -f "'$name'" >/dev/null 2>&1 || true' INT TERM
  while kill -0 "$docker_pid" 2>/dev/null; do
    sleep 30
    if kill -0 "$docker_pid" 2>/dev/null; then
      local last
      last="$(tail -n 1 "$out/$stage.log" 2>/dev/null || true)"
      printf '[V114] %-9s running, log=%s bytes | %s\n' "$stage" "$(wc -c < "$out/$stage.log")" "${last:0:110}"
    fi
  done
  local rc=0
  wait "$docker_pid" || rc=$?
  trap - INT TERM
  if [[ $rc -ne 0 ]]; then
    echo "FAILED_${stage^^}" > "$out/status.txt"
    echo "[FAIL] Full-chip ORFS $stage (exit=$rc); log tail:" >&2
    tail -n 60 "$out/$stage.log" >&2
    return 1
  fi
  echo "PASS_${stage^^}" > "$out/status.txt"
  echo "[PASS] Full-chip ORFS $stage"
}

# Stage 1: full synthesis (ROM and inferred RAM included, UNMOCKED)
echo '[V114] Running full-chip synthesis (may be memory/time intensive)'
if ! after_make synth; then exit 4; fi
# Fail closed if Yosys prunes any hard-macro bank.
if ! docker run --rm \
  --mount "type=bind,source=$PWD,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc \
  'source /OpenROAD-flow-scripts/env.sh; openroad -exit /workspace/scripts/v114_inspect_odb.tcl' \
  > "$out/inspect.log" 2>&1; then
  echo '[FAIL] Post-synthesis hard SRAM counts differ; refusing false full-chip GDS' >&2
  cat "$out/inspect.log" >&2
  echo 'FAILED_MACRO_INVENTORY' > "$out/status.txt"
  exit 5
fi
grep 'V114_' "$out/inspect.log" || true
# Stage 2 + 3: floorplan with deterministic SRAM grid and finish GDS
echo '[V114] Floorplan + 1,180 hard SRAM placements'
if ! after_make floorplan; then exit 6; fi
echo '[V114] Place/CTS/Route/streamout: full-chip GDSII'
if ! after_make finish; then exit 7; fi
if [[ ! -s "$out/results/6_final.gds" ]]; then
  echo '[FAIL] ORFS finish returned but final full-chip GDS is empty/missing' >&2
  echo 'FAILED_NO_GDS' > "$out/status.txt"
  exit 8
fi
echo 'GDS_GENERATED_UNSIGNED' > "$out/status.txt"
echo "[PASS] Full-chip GDSII trial: $out/results/6_final.gds"
echo '[LIMIT] DRC/LVS/STA and fab acceptance NOT signed off.'

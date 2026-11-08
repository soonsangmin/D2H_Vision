#!/usr/bin/env bash
# End-to-end compute/control PnR: full HandSeg + crop + full CNN; excludes storage for speed.
# WARNING output has nonfunctional memory-only macro placeholders; NOT WORKING ASIC.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-gds}"
case "$mode" in synth|gds) ;; *) echo 'Usage: bash scripts/run_v116_nearfull_gds.sh [synth|gds]'; exit 2;; esac
out=output/v116_nearfull
mkdir -p "$out"/{results,reports,logs,objects}
echo STARTED > "$out/status.txt"
trap 'python3 scripts/v116_report.py || true' EXIT
for f in config/config.mk config/config_hard_sram.mk config/v114_pdn.tcl scripts/v116_generate_views.py scripts/v116_build_sources.py rtl/memory/v116_absent_memory_blackboxes.v; do
  [[ -s "$f" ]] || { echo "[FAIL] Missing $f"; echo FAILED_PREFLIGHT > "$out/status.txt"; exit 2; }
done
for f in macros/sky130_1k/sky130_sram_1kbyte_1rw1r_32x256_8.{lef,gds} macros/sky130_1k/sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib; do
  [[ -s "$f" ]] || { echo "[FAIL] Missing real CNN SRAM view $f"; echo FAILED_REAL_SRAM_VIEWS > "$out/status.txt"; exit 2; }
done
command -v docker >/dev/null || { echo '[FAIL] Docker missing'; echo FAILED_DOCKER > "$out/status.txt"; exit 2; }
if docker ps --format '{{.Names}}' | grep -Eq '^v114_synth_'; then
 echo '[FAIL] Old V114 synthesis still running. Stop old container first.'; echo FAILED_CONCURRENT > "$out/status.txt"; exit 2
fi
sv2v_bin='.tools/sv2v/v0.0.13/sv2v'
if [[ ! -x "$sv2v_bin" ]]; then
 if [[ -s scripts/v111_install_sv2v.py ]]; then
  sv2v_bin="$(python3 scripts/v111_install_sv2v.py)"
 elif command -v sv2v >/dev/null; then sv2v_bin="$(command -v sv2v)"
 else echo '[FAIL] sv2v missing'; echo FAILED_SV2V > "$out/status.txt"; exit 2; fi
fi
python3 scripts/v116_generate_views.py
python3 scripts/v116_build_sources.py
mapfile -t sources < "$out/v116_sources.txt"
echo "[V116] Converting ${#sources[@]} files to Verilog; near-full compute top=asic_ai_top"
if ! "$sv2v_bin" -D SYNTHESIS -D ASIC_USE_SKY130_SRAM "${sources[@]}" > "$out/converted.tmp.v" 2> "$out/sv2v.log"; then
 echo FAILED_SV2V > "$out/status.txt"; tail -n 65 "$out/sv2v.log"; exit 3
fi
mv "$out/converted.tmp.v" "$out/converted.v"
if ! grep -qE '^[[:space:]]*module[[:space:]]+asic_ai_top\b' "$out/converted.v"; then
 echo '[FAIL] Missing AI compute top'; echo FAILED_TOP > "$out/status.txt"; exit 3
fi
for req in conv_layer_engine concat_upsample_engine residual_word_engine cnn_top pw_engine_expand pw_engine_project dw_engine mobilenet_head; do
 if ! grep -q "module $req" "$out/converted.v"; then
  echo "[FAIL] Missing compute module: $req"; echo FAILED_COMPUTE_SOURCE > "$out/status.txt"; exit 3
 fi
done
run_stage(){
 local stage="$1"
    local name="v116_${stage}_$$"
    local logfile="$out/$stage.log"
 echo "[V116] START $stage (log=$logfile)"
 docker run --rm --name "$name" \
  --mount "type=bind,source=$PWD,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow \
  openroad/orfs:latest bash -lc \
  "set -e; source /OpenROAD-flow-scripts/env.sh; \
   ln -sfn /workspace/params ./params; ln -sfn /workspace/rtl ./rtl; \
   make -j1 '$stage' DESIGN_CONFIG=/workspace/config/config_v116_nearfull_compute.mk \
    RESULTS_DIR=/workspace/$out/results \
    REPORTS_DIR=/workspace/$out/reports \
    LOG_DIR=/workspace/$out/logs \
    OBJECTS_DIR=/workspace/$out/objects" > "$logfile" 2>&1 &
 local pid=$! rc=0
 trap 'docker stop "'"$name"'" >/dev/null 2>&1 || true' INT TERM
 while kill -0 "$pid" 2>/dev/null; do
  sleep 20
  if kill -0 "$pid" 2>/dev/null; then
   printf '[V116] %-10s | log=%sB | %s\n' "$stage" "$(wc -c < "$logfile")" "$(tail -n 1 "$logfile" | cut -c 1-125)"
  fi
 done
 wait "$pid" || rc=$?
 trap - INT TERM
 if [[ "$rc" -ne 0 ]]; then
  echo "FAILED_${stage^^}" > "$out/status.txt"
  echo "[FAIL] stage=$stage exit=$rc"; tail -n 65 "$logfile"; return "$rc"
 fi
 echo "PASS_${stage^^}" > "$out/status.txt"
 echo "[PASS] stage=$stage"
}
run_stage synth
# Validate real compute RTL survivors and both absent memory interfaces in OpenDB.
if ! docker run --rm \
 --mount "type=bind,source=$PWD,target=/workspace" \
 --workdir /OpenROAD-flow-scripts/flow \
 openroad/orfs:latest bash -lc \
 'source /OpenROAD-flow-scripts/env.sh; openroad -exit /workspace/scripts/v116_inspect_odb.tcl' \
 > "$out/inspect.log" 2>&1; then
 echo FAILED_ODB_AUDIT > "$out/status.txt"
 echo '[FAIL] ODB macro inventory. No GDS falsely claimed.'; tail -n 75 "$out/inspect.log"; exit 4
fi
grep '^V116_' "$out/inspect.log" || true
if [[ "$mode" == synth ]]; then
 echo 'SYNTH_COMPLETE_MEMORY_ABSENT' > "$out/status.txt"
 echo "[V116] Synthesis complete, report=$out/BAO_CAO_V116.md"
 exit 0
fi
run_stage floorplan
run_stage finish
if [[ ! -s "$out/results/6_final.gds" ]]; then
 echo FAILED_GDS_ABSENT > "$out/status.txt"
 echo '[FAIL] ORFS finish returned but GDS missing'; exit 5
fi
sha256sum "$out/results/6_final.gds" > "$out/results/6_final.gds.sha256"
echo GDS_COMPUTE_LOGIC_ONLY_WITH_MISSING_MEMORY_STUBS > "$out/status.txt"
echo "[PASS] NEAR-FULL COMPUTE-ONLY GDS at $out/results/6_final.gds"
echo '[CRITICAL] GDS contains empty/nonfunctional memory marker macros. Cannot infer or fab without actual memory!'

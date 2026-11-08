#!/usr/bin/env bash
# V117 trial GDS: near-full HandSeg+ROI+CNN logic; NONFUNCTIONAL SRAM/ROM placeholders.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-gds}"
case "$mode" in synth|gds) ;; *) echo 'Usage: bash scripts/run_v117_nearfull_gds.sh [synth|gds]'; exit 2;; esac
out=output/v117_nearfull
mkdir -p "$out"/{results,reports,logs,objects}
echo STARTED > "$out/status.txt"
trap 'python3 scripts/v117_report.py || true' EXIT
for f in scripts/v116_generate_views.py scripts/v116_build_sources.py scripts/v117_generate_views.py scripts/v117_build_sources.py config/config_v116_nearfull_compute.mk config/config_v117_nearfull_compute.mk rtl/memory/v117_absent_memory_blackboxes.v;do
 [[ -s "$f" ]] || { echo "[FAIL] Missing prerequisite $f"; echo FAILED_PREFLIGHT > "$out/status.txt"; exit 2; }
done
for f in macros/sky130_1k/sky130_sram_1kbyte_1rw1r_32x256_8.{lef,gds} macros/sky130_1k/sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib;do
 [[ -s "$f" ]] || { echo "[FAIL] Real CNN SRAM view missing $f"; echo FAILED_MACRO_VIEWS > "$out/status.txt";exit 2; }
done
command -v docker >/dev/null || { echo '[FAIL] docker not found';exit 2; }
if ! docker info >/dev/null 2>&1;then echo '[FAIL] Docker engine unavailable';echo FAILED_DOCKER > "$out/status.txt"; exit 2; fi
sv2v_bin=.tools/sv2v/v0.0.13/sv2v
if [[ ! -x "$sv2v_bin" ]];then
  if [[ -s scripts/v111_install_sv2v.py ]];then sv2v_bin="$(python3 scripts/v111_install_sv2v.py)";
  elif command -v sv2v >/dev/null;then sv2v_bin="$(command -v sv2v)";
  else echo '[FAIL] sv2v unavailable';echo FAILED_SV2V > "$out/status.txt";exit 2;fi
fi
python3 scripts/v116_generate_views.py
python3 scripts/v117_generate_views.py
python3 scripts/v117_build_sources.py
mapfile -t sources < "$out/v117_sources.txt"
echo "[V117] Converting ${#sources[@]} RTL source files; near-full top=asic_ai_top"
if ! "$sv2v_bin" -D SYNTHESIS -D ASIC_USE_SKY130_SRAM "${sources[@]}" > "$out/converted.tmp.v" 2> "$out/sv2v.log";then
 echo FAILED_SV2V > "$out/status.txt"; tail -n 50 "$out/sv2v.log";exit 3
fi
mv "$out/converted.tmp.v" "$out/converted.v"
for m in asic_ai_top conv_layer_engine concat_upsample_engine residual_word_engine cnn_top pw_engine_expand pw_engine_project dw_engine mobilenet_head;do
 grep -q "module $m" "$out/converted.v" || { echo "[FAIL] Missing compute module $m";echo FAILED_COMPUTE_RTL > "$out/status.txt";exit 3; }
done
stage_run(){
 local stage="$1"
 local name="v117_${stage}_$$"
 local logfile="$out/$stage.log"
 local limit_sec=2400
 case "$stage" in floorplan) limit_sec=900;; finish) limit_sec=1800;; esac
 echo "[V118] START $stage (limit=${limit_sec}s, quick ABC); log=$logfile"
 # Limit time per stage and container memory so a slow Yosys doesn't freeze Docker Desktop.
 timeout -s TERM -k 90s "$limit_sec" docker run --rm --memory=6g --name "$name" \
  --mount "type=bind,source=$PWD,target=/workspace" \
  --mount "type=bind,source=$PWD/config/v118_synth_preamble.tcl,target=/OpenROAD-flow-scripts/flow/scripts/synth_preamble.tcl,readonly" \
  --mount "type=bind,source=/mnt/d/ASIC_WORK/V118/tmp,target=/worktmp" \
  --env TMPDIR=/worktmp --env TMP=/worktmp \
  --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc \
  "set -e; source /OpenROAD-flow-scripts/env.sh; \
   ln -sfn /workspace/params ./params; ln -sfn /workspace/rtl ./rtl; \
   make -j1 '$stage' DESIGN_CONFIG=/workspace/config/config_v117_nearfull_compute.mk \
   RESULTS_DIR=/workspace/$out/results REPORTS_DIR=/workspace/$out/reports \
   LOG_DIR=/workspace/$out/logs OBJECTS_DIR=/workspace/$out/objects" > "$logfile" 2>&1 &
 local pid=$! rc=0
 trap 'docker stop "'"$name"'" >/dev/null 2>&1 || true' INT TERM
 while kill -0 "$pid" 2>/dev/null;do
  sleep 15
  if kill -0 "$pid" 2>/dev/null;then
   printf '[V117] %-9s log=%sB | %s\n' "$stage" "$(wc -c < "$logfile")" "$(tail -n 1 "$logfile" | cut -c 1-130)"
  fi
 done
 wait "$pid" || rc=$?
 trap - INT TERM
 if [[ "$rc" != 0 ]];then
  echo "FAILED_${stage^^}_EXIT_${rc}" > "$out/status.txt"
  docker stop "$name" >/dev/null 2>&1 || true
  echo "[FAIL] stage=$stage exit=$rc"; tail -n 55 "$logfile";return "$rc"
 fi
 echo "PASS_${stage^^}" > "$out/status.txt"
 echo "[PASS] stage=$stage"
}
stage_run synth
# Audit ACTUAL OpenDB, do not trust source-only checks.
if ! docker run --rm --memory=3g \
 --mount "type=bind,source=$PWD,target=/workspace" \
  --mount "type=bind,source=$PWD/config/v118_synth_preamble.tcl,target=/OpenROAD-flow-scripts/flow/scripts/synth_preamble.tcl,readonly" \
  --mount "type=bind,source=/mnt/d/ASIC_WORK/V118/tmp,target=/worktmp" \
  --env TMPDIR=/worktmp --env TMP=/worktmp \
 --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc \
 'source /OpenROAD-flow-scripts/env.sh;openroad -exit /workspace/scripts/v117_inspect_odb.tcl' > "$out/inspect.log" 2>&1;then
 echo FAILED_ODB_AUDIT > "$out/status.txt"
 echo '[FAIL] OpenDB inventory failure. No GDS claimed.'; tail -n 60 "$out/inspect.log";exit 4
fi
grep '^V117_' "$out/inspect.log" || true
if [[ "$mode" == synth ]];then
 echo SYNTH_OK_MEMORY_NONFUNCTIONAL > "$out/status.txt";exit 0
fi
stage_run floorplan
stage_run finish
[[ -s "$out/results/6_final.gds" ]] || { echo FAILED_MISSING_GDS > "$out/status.txt"; echo '[FAIL] GDS not produced'; exit 5; }
sha256sum "$out/results/6_final.gds" > "$out/results/6_final.gds.sha256"
echo GDS_PRESENT_COMPUTE_ONLY_MISSING_MEMORY > "$out/status.txt"
echo "[PASS] GDSII exists: $out/results/6_final.gds"
echo '[WARNING] NONFUNCTIONAL memory placeholders. NOT a working ASIC. NOT tapeout-ready.'

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/v111_prepare_hierarchy.py
if ! command -v docker >/dev/null; then
  echo '[BLOCKED] Docker required for ORFS Yosys hierarchy elaboration' >&2
  exit 2
fi
out=output/v111_ai_top_hierarchy
if [ -n "${SV2V_BIN:-}" ]; then
  sv2v_bin="$SV2V_BIN"
else
  sv2v_bin="$(python3 scripts/v111_install_sv2v.py)"
fi
if [ ! -x "$sv2v_bin" ]; then
  echo "[FAIL] sv2v binary is not executable: $sv2v_bin" >&2
  exit 2
fi
mapfile -t rtl_files < "$out/source_files.txt"
echo "[START] Convert ${#rtl_files[@]} SystemVerilog files to Verilog using sv2v"
rm -f "$out/converted.tmp.v"
if ! "$sv2v_bin" \
     -D SYNTHESIS -D ASIC_USE_SKY130_SRAM \
     -D V107_HARD_FEATURE_SRAM -D V109_SINGLE_COPY_SRAM \
     "${rtl_files[@]}" \
     > "$out/converted.tmp.v" 2> "$out/sv2v.log"; then
  echo '[FAIL] sv2v conversion failed. Last messages:' >&2
  tail -n 65 "$out/sv2v.log" >&2
  rm -f "$out/converted.tmp.v"
  exit 3
fi
if ! grep -qE '^[[:space:]]*module[[:space:]]+asic_ai_onchip_top\b' "$out/converted.tmp.v"; then
  echo '[FAIL] Converted source does not contain asic_ai_onchip_top' >&2
  exit 3
fi
mv "$out/converted.tmp.v" "$out/converted.v"
echo '[PASS] sv2v conversion completed; launching Yosys 0.64 hierarchy-only elaboration'
if ! docker run --rm --mount "type=bind,source=$PWD,target=/workspace" \
   --workdir /workspace openroad/orfs:latest bash -lc \
   'set -euo pipefail; source /OpenROAD-flow-scripts/env.sh; yosys -s /workspace/output/v111_ai_top_hierarchy/elaborate.ys' \
  > "$out/elaboration.log" 2>&1; then
  echo '[FAIL] Yosys hierarchy elaboration failed. Last lines:' >&2
  tail -n 65 "$out/elaboration.log" >&2
  exit 4
fi
python3 scripts/v111_check_hierarchy_rtlil.py

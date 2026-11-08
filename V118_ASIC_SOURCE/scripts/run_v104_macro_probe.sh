#!/usr/bin/env bash
# A REAL-VIEW, ONE-MACRO ORFS SYNTHESIS PROBE. NOT the full ASIC.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 scripts/check_macro_views.py
command -v docker >/dev/null || { echo 'ERROR: Docker required'; exit 2; }
mkdir -p output/v104_macro_probe/{results,reports,logs,objects}
cat > output/v104_macro_probe/PROBE_ONLY.txt <<'TXT'
ONE SRAM MACRO PROBE ONLY: NOT THE AI TOP, NOT TAPEOUT-READY.
All other HandSeg/CNN inferred memories remain to be resolved.
TXT
docker run --rm --mount "type=bind,source=$ROOT,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc '
  set -euo pipefail
  source /OpenROAD-flow-scripts/env.sh
  cd /OpenROAD-flow-scripts/flow
  make -j1 synth DESIGN_CONFIG=/workspace/config/config_macro_probe.mk \
    SYNTH_MOCK_LARGE_MEMORIES=0 \
    RESULTS_DIR=/workspace/output/v104_macro_probe/results \
    REPORTS_DIR=/workspace/output/v104_macro_probe/reports \
    LOG_DIR=/workspace/output/v104_macro_probe/logs \
    OBJECTS_DIR=/workspace/output/v104_macro_probe/objects \
    2>&1 | tee /workspace/output/v104_macro_probe/screening.log
  '
# For a macro integration PASS, the final netlist must retain leaf macro.
if ! grep -Eq 'sky130_sram_1kbyte_1rw1r_32x256_8' \
      output/v104_macro_probe/results/1_2.v 2>/dev/null; then
    echo '[CHECK] Macro cell not verified at expected netlist path; inspect ORFS results before declaring PASS.'
    find output/v104_macro_probe/results -maxdepth 1 -type f -printf '%f\n'
    exit 4
fi
echo '[OK] Macro found in probe gate-level netlist (NOT AI full-system verification)'

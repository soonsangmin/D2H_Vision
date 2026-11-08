#!/usr/bin/env bash
# Synthesizes the entire FULL-DEPTH AI. Large memory, potentially huge runtime.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_v105_static.py
python3 scripts/check_macro_views.py
if [ "${I_UNDERSTAND_FULL_ONCHIP_COST:-}" != 'YES' ]; then
    echo '[BLOCKED] Memory architecture is not yet macro-mapped for final PnR.'
    echo 'Estimated internal scratch feature RAM alone: 8 MiB / 67,108,864 bits.'
    echo 'Full memory_map to flip-flops can exhaust RAM and exceed SKY130 die limits.'
    echo 'To run synthesis EXPERIMENTALLY, set I_UNDERSTAND_FULL_ONCHIP_COST=YES.'
    exit 3
fi
mkdir -p output/v105_full_synth/{results,reports,logs,objects}
docker run --rm \
  --mount "type=bind,source=$PWD,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow \
  openroad/orfs:latest bash -lc '
    set -euo pipefail
    source /OpenROAD-flow-scripts/env.sh
    ln -sfn /workspace/rtl ./rtl
    ln -sfn /workspace/params ./params
    make -j1 synth \
      DESIGN_CONFIG=/workspace/config/config_onchip.mk \
      SYNTH_MOCK_LARGE_MEMORIES=0 \
      SYNTH_MEMORY_MAX_BITS=16777216 \
      RESULTS_DIR=/workspace/output/v105_full_synth/results \
      REPORTS_DIR=/workspace/output/v105_full_synth/reports \
      LOG_DIR=/workspace/output/v105_full_synth/logs \
      OBJECTS_DIR=/workspace/output/v105_full_synth/objects
  ' > output/v105_full_synth/build.log 2>&1
rc=$?
tail -n 50 output/v105_full_synth/build.log
exit "$rc"

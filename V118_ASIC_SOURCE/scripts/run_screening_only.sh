#!/usr/bin/env bash
# V1.01 ONLY: a non-functional screening synthesis to find more HDL errors.
# Large inferred memories are MOCKED to 1-row, so the resulting netlist is
# FUNCTIONALLY INCORRECT and MUST NOT be used as a chip/GDS/signoff deliverable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/output/screening_only"
mkdir -p "$DIR"/{results,reports,logs,objects}
printf '%s\n' 'SCREENING ONLY: memory data are intentionally mocked.' \
 'DO NOT USE THIS NETLIST AS THE ACTUAL AI CHIP.' > "$DIR/NOT_FOR_TAPEOUT.txt"
docker run --rm --mount "type=bind,source=$ROOT,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc '
  set -euo pipefail
  source /OpenROAD-flow-scripts/env.sh
  cd /OpenROAD-flow-scripts/flow
  ln -sfn /workspace/rtl ./rtl
  make -j1 synth DESIGN_CONFIG=/workspace/config/config.mk \
    SYNTH_MEMORY_MAX_BITS=4096 \
    SYNTH_MOCK_LARGE_MEMORIES=1 \
    RESULTS_DIR=/workspace/output/screening_only/results \
    REPORTS_DIR=/workspace/output/screening_only/reports \
    LOG_DIR=/workspace/output/screening_only/logs \
    OBJECTS_DIR=/workspace/output/screening_only/objects \
    2>&1 | tee /workspace/output/screening_only/screening.log
  '

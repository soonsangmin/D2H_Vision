#!/usr/bin/env bash
# Fast ORFS memory audit: expected to identify RTL arrays larger than 4096 bits.
# This run does NOT produce a valid GDS and MAY exit nonzero by design.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/output/audit"/{results,reports,logs,objects}
docker run --rm --mount "type=bind,source=$ROOT,target=/workspace" \
  --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc '
  source /OpenROAD-flow-scripts/env.sh
  cd /OpenROAD-flow-scripts/flow
  ln -sfn /workspace/rtl ./rtl
  make synth -j2 DESIGN_CONFIG=/workspace/config/config.mk \
    SYNTH_MEMORY_MAX_BITS=4096 \
    RESULTS_DIR=/workspace/output/audit/results \
    REPORTS_DIR=/workspace/output/audit/reports \
    LOG_DIR=/workspace/output/audit/logs \
    OBJECTS_DIR=/workspace/output/audit/objects \
    > /workspace/output/audit/audit.log 2>&1
  status=$?
  tail -n 80 /workspace/output/audit/audit.log
  exit $status
  '

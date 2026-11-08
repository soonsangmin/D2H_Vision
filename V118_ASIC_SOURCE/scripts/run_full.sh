#!/usr/bin/env bash
# This version is NOT full-memory-mapped. Explicit opt-in is required.
set -euo pipefail
if [[ "${V102_EXPERIMENTAL_ENABLE:-0}" != "1" ]]; then
  echo '[STOP] V1.02 still has large unmapped memories; full synth/PnR would be misleading.' >&2
  echo '[STOP] See docs/V102_IMPLEMENTATION_VI.md. Use run_screening_only.sh instead.' >&2
  exit 3
fi
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! docker image inspect openroad/orfs:latest >/dev/null 2>&1; then
  echo 'ERROR: docker image openroad/orfs:latest missing or daemon not running' >&2
  exit 1
fi
mkdir -p "$ROOT/output"/{results,reports,logs,objects}
# All results are host-mounted and persist after Docker exits.
docker run --rm --mount "type=bind,source=$ROOT,target=/workspace"    --workdir /OpenROAD-flow-scripts/flow openroad/orfs:latest bash -lc '
   set -euo pipefail
   source /OpenROAD-flow-scripts/env.sh
   cd /OpenROAD-flow-scripts/flow
   ln -sfn /workspace/rtl ./rtl
   make -j2 DESIGN_CONFIG=/workspace/config/config.mk       RESULTS_DIR=/workspace/output/results       REPORTS_DIR=/workspace/output/reports       LOG_DIR=/workspace/output/logs       OBJECTS_DIR=/workspace/output/objects       2>&1 | tee /workspace/output/orfs_full.log
   '

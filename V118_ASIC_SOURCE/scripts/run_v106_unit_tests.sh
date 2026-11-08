#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_v105_static.py
python3 scripts/v106_bank_depth_audit.py
if ! command -v iverilog >/dev/null 2>&1 || ! command -v vvp >/dev/null 2>&1; then
    echo '[BLOCKED] Icarus Verilog (iverilog + vvp) is required for HDL tests'
    exit 2
fi
mkdir -p output/v106_tests
iverilog -g2012 -s tb_v106_feature_banks -o output/v106_tests/feature_tb.vvp \
    rtl/memory/reference_feature_memory.sv tests/tb_v106_feature_banks.sv
vvp output/v106_tests/feature_tb.vvp
bash scripts/run_v105_unit_tests.sh
printf '%s\n' '[OK] V106 static geometry audit and RAM protocol regression complete'

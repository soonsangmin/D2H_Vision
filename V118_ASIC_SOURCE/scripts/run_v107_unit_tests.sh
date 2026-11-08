#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_v107_static.py
python3 scripts/v107_geometry_walk.py
bash scripts/run_v106_unit_tests.sh
if ! command -v iverilog >/dev/null 2>&1; then
    echo '[BLOCKED] install iverilog / Icarus Verilog first'; exit 2
fi
MACRO=sky130_sram_2kbyte_1rw1r_32x512_8
MODEL="macros/sky130_2k/${MACRO}.v"
if [ ! -s "$MODEL" ]; then
    echo '[BLOCKED] Missing real OpenRAM Verilog model. Run: bash scripts/v107_fetch_macro_views.sh'
    exit 2
fi
mkdir -p output/v107_tests
iverilog -g2012 -s tb_v107_feature_macro -D V107_HARD_FEATURE_SRAM \
  -o output/v107_tests/v107_feature_macro.vvp \
  -I . sim/v107_openram_model_include.sv \
  rtl/memory/v107_handseg_feature_sram_bank.sv \
  rtl/memory/v107_handseg_feature_memory_macro.sv \
  rtl/memory/reference_feature_memory.sv \
  tests/tb_v107_feature_macro.sv
vvp output/v107_tests/v107_feature_macro.vvp
printf '%s\n' '[OK] V107 static + V106 regression + macro behavioral test PASS (not PnR/GDS)'

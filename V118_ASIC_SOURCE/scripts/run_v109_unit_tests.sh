#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_v109_single_copy.py
if ! command -v iverilog >/dev/null 2>&1; then
  echo '[BLOCKED] Install Icarus Verilog / iverilog first'; exit 2
fi
MODEL=macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.v
if [[ ! -s "$MODEL" ]]; then
  echo '[BLOCKED] Missing original SRAM .v model: bash scripts/v107_fetch_macro_views.sh'; exit 2
fi
mkdir -p output/v109_tests
iverilog -g2012 -s tb_v109_feature_macro -D V107_HARD_FEATURE_SRAM -D V109_SINGLE_COPY_SRAM \
  -o output/v109_tests/v109_feature_macro.vvp -I . \
  sim/v107_openram_model_include.sv \
  rtl/memory/v109_handseg_feature_sram_bank.sv \
  rtl/memory/v109_handseg_feature_memory_macro.sv \
  rtl/memory/reference_feature_memory.sv \
  tests/tb_v109_feature_macro.sv \
  > output/v109_tests/compile.log 2>&1 || {
    tail -n 70 output/v109_tests/compile.log; exit 3;
  }
if vvp output/v109_tests/v109_feature_macro.vvp > output/v109_tests/simulation.log 2>&1; then
  grep '^PASS tb_v109_feature_macro' output/v109_tests/simulation.log || {
    tail -n 55 output/v109_tests/simulation.log; exit 4;
  }
  echo '[PASS] V109 2-macro OpenRAM model protocol (8 banks; 2R; read/write; backpressure; tile arbitration)'
else
  echo '[FAIL] V109 Verilog simulation'; tail -n 60 output/v109_tests/simulation.log; exit 5
fi

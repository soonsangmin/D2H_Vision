#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_v105_static.py
if ! command -v iverilog >/dev/null; then
  echo '[BLOCKED] Icarus Verilog (iverilog) not installed'; exit 2
fi
mkdir -p output/v105_onchip_test
iverilog -g2012 -s tb_v105_onchip_frame_memory \
  -o output/v105_onchip_test/frame_tb.vvp \
  rtl/memory/asic_onchip_frame_memory.sv tests/tb_v105_onchip_frame_memory.sv
vvp output/v105_onchip_test/frame_tb.vvp

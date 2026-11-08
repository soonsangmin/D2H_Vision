#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v iverilog >/dev/null 2>&1; then
  echo '[ERROR] iverilog missing on Ubuntu. No installation performed.' >&2
  exit 2
fi
mkdir -p "$ROOT/output/unit"
iverilog -g2012 -s tb_rgb96_writer -o "$ROOT/output/unit/tb_writer.vvp"   "$ROOT/rtl/integration/asic_rgb96_ddr_writer.sv"   "$ROOT/tests/tb_rgb96_writer.sv"
vvp "$ROOT/output/unit/tb_writer.vvp"
iverilog -g2012 -s tb_ddr_read_mux -o "$ROOT/output/unit/tb_arb.vvp"   "$ROOT/rtl/integration/ai_ddr_read_mux.sv"   "$ROOT/tests/tb_ddr_read_mux.sv"
vvp "$ROOT/output/unit/tb_arb.vvp"
iverilog -g2012 -s tb_rgb96_classifier -o "$ROOT/output/unit/tb_reader.vvp" \
  "$ROOT/rtl/integration/asic_rgb96_ddr_classifier.sv" \
  "$ROOT/tests/tb_rgb96_classifier.sv"
vvp "$ROOT/output/unit/tb_reader.vvp"
echo '[OK] Protocol unit tests complete (NOT CNN functional equivalence).'


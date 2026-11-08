#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v iverilog >/dev/null || { echo "ERROR: install iverilog"; exit 2; }
mkdir -p output/v103_tests
iverilog -g2012 -s tb_asic_sram_1r1w -o output/v103_tests/ram.vvp \
  rtl/memory/asic_sram_1r1w.sv tests/tb_asic_sram_1r1w.sv
vvp output/v103_tests/ram.vvp
for shape in "4 3" "96 24" "48 64" "24 128"; do
  read -r width ch <<< "$shape"
  iverilog -g2012 -s tb_fifo_sram_equivalence \
    -Ptb_fifo_sram_equivalence.WIDTH="$width" \
    -Ptb_fifo_sram_equivalence.CHANNELS="$ch" \
    -o "output/v103_tests/fifo_${width}_${ch}.vvp" \
    rtl/memory/asic_sram_1r1w.sv \
    rtl/classifier/stream_interstage_row_fifo_hwc_stage2.v \
    tests/reference_stream_interstage_row_fifo_v102.sv \
    tests/tb_fifo_sram_equivalence.sv
  vvp "output/v103_tests/fifo_${width}_${ch}.vvp"
done
bash scripts/run_unit_tests.sh
printf '\n[OK] V1.03 protocol and SRAM-equivalence tests complete\n'

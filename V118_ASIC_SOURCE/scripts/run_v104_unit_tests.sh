#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v iverilog >/dev/null || { echo 'ERROR: iverilog required'; exit 2; }
mkdir -p output/v104_tests
# Ensure behavioral mode remains unchanged: V1.03 unit suite.
bash scripts/run_v103_unit_tests.sh
# Hard-macro path uses a protocol stub only, never a fake LEF/Liberty/GDS.
iverilog -g2012 -DASIC_USE_SKY130_SRAM -s tb_v104_byte_addressing \
  -o output/v104_tests/address.vvp \
  rtl/memory/asic_sram_1r1w.sv \
  tests/models/sky130_sram_1kbyte_1rw1r_32x256_8.sv \
  tests/tb_v104_byte_addressing.sv
vvp output/v104_tests/address.vvp
# Larger FIFO shapes match the source CNN instances; no mock RAM shrink.
for shape in '4 3' '96 24' '96 32' '48 64' '24 128'; do
  read -r width ch <<< "$shape"
  iverilog -g2012 -DASIC_USE_SKY130_SRAM -s tb_fifo_sram_equivalence \
    -Ptb_fifo_sram_equivalence.WIDTH="$width" \
    -Ptb_fifo_sram_equivalence.CHANNELS="$ch" \
    -o "output/v104_tests/fifo_macro_${width}_${ch}.vvp" \
    rtl/memory/asic_sram_1r1w.sv \
    tests/models/sky130_sram_1kbyte_1rw1r_32x256_8.sv \
    rtl/classifier/stream_interstage_row_fifo_hwc_stage2.v \
    tests/reference_stream_interstage_row_fifo_v102.sv \
    tests/tb_fifo_sram_equivalence.sv
  vvp "output/v104_tests/fifo_macro_${width}_${ch}.vvp"
done
python3 scripts/verify_v104_static.py
printf '\n[OK] V1.04 SRAM banking and FIFO regression complete (PROTOCOL SIMULATION, NOT PnR)\n'

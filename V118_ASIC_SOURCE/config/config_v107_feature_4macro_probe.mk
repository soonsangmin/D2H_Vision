# Synthesis / OpenDB linkage test of the exact V107 64bit 2R1W tile RTL.
# Exactly 4x sky130_2k; does NOT imply 2256 macro full-chip fit.
include /workspace/config/config.mk
export DESIGN_NAME = v107_handseg_feature_4macro_probe
export DESIGN_NICKNAME = v107_four_sram_tile
export VERILOG_FILES = /workspace/asic/v107_handseg_feature_4macro_probe.sv /workspace/rtl/memory/v107_handseg_feature_sram_bank.sv /workspace/rtl/memory/sky130_sram_2kbyte_1rw1r_32x512_8_blackbox.v
export ADDITIONAL_LEFS = /workspace/macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.lef
export ADDITIONAL_LIBS = /workspace/macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib
export ADDITIONAL_GDS = /workspace/macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.gds
export SDC_FILE = /workspace/config/constraint_macro_probe.sdc
export SYNTH_MOCK_LARGE_MEMORIES = 0
export SYNTH_MEMORY_MAX_BITS = 4096
export CORE_UTILIZATION = 25

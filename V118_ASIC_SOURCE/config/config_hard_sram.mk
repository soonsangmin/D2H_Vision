# V1.04 HARD-MACRO CONCEPT INTEGRATION. Do NOT run full PnR yet.
# Requires real SRAM physical and timing views at exact paths below.
# Remaining memory inference in CNN/HandSeg must be mapped separately.
include /workspace/config/config.mk
export VERILOG_DEFINES += -D ASIC_USE_SKY130_SRAM
export VERILOG_FILES += /workspace/rtl/memory/sky130_sram_1kbyte_1rw1r_32x256_8_blackbox.v
export ADDITIONAL_LEFS += /workspace/macros/sky130_1k/sky130_sram_1kbyte_1rw1r_32x256_8.lef
export ADDITIONAL_LIBS += /workspace/macros/sky130_1k/sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib
export ADDITIONAL_GDS += /workspace/macros/sky130_1k/sky130_sram_1kbyte_1rw1r_32x256_8.gds
export SYNTH_MOCK_LARGE_MEMORIES = 0
# Remaining inferred RAMs still exist and are NOT suitable for final PnR.
export SYNTH_MEMORY_MAX_BITS = 1048576

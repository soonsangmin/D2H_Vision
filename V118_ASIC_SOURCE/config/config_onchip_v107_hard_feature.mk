# EXPERIMENTAL HARD-SRAM handseg feature-memory mapping: V1.07.
# Entire CNN, weight storage, snapshot and other RAMs are NOT mapped; do not
# run whole-chip PnR or assume ASIC tapeout readiness.
include /workspace/config/config_onchip.mk
export DESIGN_NICKNAME = ai_onchip_v107_feature_sram
export VERILOG_DEFINES += -D V107_HARD_FEATURE_SRAM
export VERILOG_FILES += /workspace/rtl/memory/v107_handseg_feature_sram_bank.sv
export VERILOG_FILES += /workspace/rtl/memory/v107_handseg_feature_memory_macro.sv
export VERILOG_FILES += /workspace/rtl/memory/sky130_sram_2kbyte_1rw1r_32x512_8_blackbox.v
export ADDITIONAL_LEFS += /workspace/macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.lef
export ADDITIONAL_LIBS += /workspace/macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib
export ADDITIONAL_GDS += /workspace/macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.gds
export SYNTH_MOCK_LARGE_MEMORIES = 0

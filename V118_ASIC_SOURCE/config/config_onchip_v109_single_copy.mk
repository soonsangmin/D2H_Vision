# V109 ON-CHIP OPTION. Experimental memory topology, NOT a passed full-chip tapeout.
include /workspace/config/config_onchip_v107_hard_feature.mk
export DESIGN_NICKNAME = ai_onchip_v109_single_copy_sram
export VERILOG_DEFINES += -D V109_SINGLE_COPY_SRAM
export VERILOG_FILES += /workspace/rtl/memory/v109_handseg_feature_sram_bank.sv
export VERILOG_FILES += /workspace/rtl/memory/v109_handseg_feature_memory_macro.sv
export SYNTH_MOCK_LARGE_MEMORIES = 0

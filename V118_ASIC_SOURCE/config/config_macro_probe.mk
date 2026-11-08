# Single macro ORFS integration probe only. Never interpret as complete ASIC.
include /workspace/config/config_hard_sram.mk
export DESIGN_NAME = asic_sram_macro_probe
export DESIGN_NICKNAME = ai_sram_1k_probe
export VERILOG_FILES = /workspace/asic/asic_sram_macro_probe.sv /workspace/rtl/memory/asic_sram_1r1w.sv /workspace/rtl/memory/sky130_sram_1kbyte_1rw1r_32x256_8_blackbox.v
export SDC_FILE = /workspace/config/constraint_macro_probe.sdc
export SYNTH_MEMORY_MAX_BITS = 4096
export SYNTH_MOCK_LARGE_MEMORIES = 0
export CORE_UTILIZATION = 20

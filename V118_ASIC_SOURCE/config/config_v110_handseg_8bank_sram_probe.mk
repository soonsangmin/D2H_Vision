# V110: Full HandSeg feature-memory subsystem only (8 banks, 1128 hard SRAMs).
# Stops at synthesis OpenDB. NOT a 1128-macro floorplan, not AI top, not GDS.
include /workspace/config/config.mk
export DESIGN_NAME = v110_handseg_8bank_sram_probe
export DESIGN_NICKNAME = v110_handseg_1128_sram_subsystem
export VERILOG_FILES = /workspace/asic/v110_handseg_8bank_sram_probe.sv \
  /workspace/rtl/memory/reference_feature_memory.sv \
  /workspace/rtl/memory/v109_handseg_feature_memory_macro.sv \
  /workspace/rtl/memory/v109_handseg_feature_sram_bank.sv \
  /workspace/rtl/memory/sky130_sram_2kbyte_1rw1r_32x512_8_blackbox.v
export VERILOG_DEFINES += -D V107_HARD_FEATURE_SRAM -D V109_SINGLE_COPY_SRAM
export ADDITIONAL_LEFS = /workspace/macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.lef
export ADDITIONAL_LIBS = /workspace/macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib
export ADDITIONAL_GDS = /workspace/macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.gds
export SDC_FILE = /workspace/config/constraint_macro_probe.sdc
export SYNTH_MOCK_LARGE_MEMORIES = 0
# Logic utilization irrelevant: this run DOES NOT FLOORPLAN.
export CORE_UTILIZATION = 25

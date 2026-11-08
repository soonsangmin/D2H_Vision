# V1.05: true full-onchip AI hierarchy (HandSeg + crop + full CNN).
# NO DDR/FPGA required. Not yet validated physical design; all RAMs UNMOCKED.
include /workspace/config/config_hard_sram.mk
export DESIGN_NAME = asic_ai_onchip_top
export DESIGN_NICKNAME = ai_all_onchip_v105
export VERILOG_FILES += /workspace/asic/asic_ai_local_core.sv /workspace/asic/asic_ai_onchip_top.sv /workspace/rtl/memory/asic_onchip_frame_memory.sv
export SYNTH_MOCK_LARGE_MEMORIES = 0
# V1.06: reference_feature_memory uses schedule-bounded 64-bit banks; no artificial shrink.
export SYNTH_MEMORY_MAX_BITS = 16777216
# Choose 10 MHz as initial target only, timing not yet validated.

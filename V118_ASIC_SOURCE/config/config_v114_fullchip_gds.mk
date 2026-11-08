# V1.14: full AI top; REAL SRAM macros + UNMOCKED inferred memories.
# Source flattened in front-end only by sv2v (preserves RTL semantics).
# NOT tapeout-signoff configuration (no padframe; macro DRC known nonzero).
include /workspace/config/config_onchip_v109_single_copy.mk
export DESIGN_NAME := asic_ai_onchip_top
export DESIGN_NICKNAME := ai_v114_full_chip_attempt
export SYNTH_HDL_FRONTEND :=
export VERILOG_FILES := /workspace/output/v114_fullchip/converted.v
export SYNTH_MOCK_LARGE_MEMORIES := 0
# Maximum single inferred memory supported by existing RTL is below 16 Mbit.
export SYNTH_MEMORY_MAX_BITS := 16777216
# Allocate a large die; physical trial ONLY, possibly too large for a real reticle.
unexport CORE_UTILIZATION
export DIE_AREA := 0 0 30000 30000
export CORE_AREA := 150 150 29850 29850
export PLACE_DENSITY := 0.35
export MACRO_PLACEMENT_TCL := /workspace/config/v114_macro_grid.tcl
export PDN_TCL := /workspace/config/v114_pdn.tcl
# Preserve SDC and all physical SRAM views inherited from V109/V107.

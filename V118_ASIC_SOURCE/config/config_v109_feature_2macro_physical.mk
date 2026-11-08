# V1.09: PHYSICAL EXPERIMENT ONLY - one 64-bit x 512 2R1W tile, two real SRAMs.
# No RTL change and no memory mocking. Not the full HandSeg/CNN ASIC.
include /workspace/config/config_v109_feature_2macro_probe.mk
export DESIGN_NICKNAME = v109_2macro_tile_physical
# Mutual exclusion: ORFS must use DIE_AREA/CORE_AREA, not utilization mode.
export CORE_UTILIZATION =
export DIE_AREA = 0 0 1780 800
export CORE_AREA = 40 40 1740 760
export MACRO_PLACEMENT_TCL = /workspace/config/v109_macro_placement.tcl
export PDN_TCL = /workspace/config/v109_pdn.tcl
export PLACE_DENSITY = 0.42
export MACRO_HALO_X = 8
export MACRO_HALO_Y = 8
export SYNTH_MOCK_LARGE_MEMORIES = 0

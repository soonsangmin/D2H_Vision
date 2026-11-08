# V1.08: PHYSICAL EXPERIMENT ONLY - one 64-bit x 512 2R1W tile, four real SRAMs.
# No RTL change and no memory mocking. Not the full HandSeg/CNN ASIC.
include /workspace/config/config_v107_feature_4macro_probe.mk
export DESIGN_NICKNAME = v108_4macro_tile_physical
# Mutual exclusion: ORFS must use DIE_AREA/CORE_AREA, not utilization mode.
export CORE_UTILIZATION =
export DIE_AREA = 0 0 1780 1250
export CORE_AREA = 40 40 1740 1210
export MACRO_PLACEMENT_TCL = /workspace/config/v108_macro_placement.tcl
export PDN_TCL = /workspace/config/v108_pdn.tcl
export PLACE_DENSITY = 0.42
export MACRO_HALO_X = 8
export MACRO_HALO_Y = 8
export SYNTH_MOCK_LARGE_MEMORIES = 0

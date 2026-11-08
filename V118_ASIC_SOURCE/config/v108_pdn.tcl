# ORFS sky130hd connects VDD/VSS on stdcells; OpenRAM macro uses vccd1/vssd1.
# Add mapping BEFORE platform pdn.tcl issues global_connect.
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^vccd1$} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^vssd1$} -ground
source $::env(PLATFORM_DIR)/pdn.tcl

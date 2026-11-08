# Connect SRAM vccd1 / vssd1 to platform global supplies.
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^vccd1$} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^vssd1$} -ground
source $::env(PLATFORM_DIR)/pdn.tcl

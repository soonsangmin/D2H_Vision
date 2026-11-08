# Two SRAMs, placed without assuming specific synthesized instance ordering.
# Macro LEF size: 683.1um x 416.54um, fixed 1x2 pattern, R0.
set target_master "sky130_sram_2kbyte_1rw1r_32x512_8"
set block [ord::get_db_block]
set macro_names [list]
foreach inst [$block getInsts] {
    if {[[$inst getMaster] getName] eq $target_master} {
        lappend macro_names [$inst getName]
    }
}
set macro_names [lsort $macro_names]
if {[llength $macro_names] != 2} {
    error "V109 expected 2 SRAM macro instances but found [llength $macro_names]: $macro_names"
}
# All macro rectangles within CORE_AREA 40 40 1740 760 with >100um channels.
set locations {{150 170} {950 170}}
for {set i 0} {$i < 2} {incr i} {
    set n [lindex $macro_names $i]
    set xy [lindex $locations $i]
    puts "V109 PLACE_MACRO name={$n} location={$xy} orient=R0"
    place_macro -macro_name $n -location $xy -orientation R0
}

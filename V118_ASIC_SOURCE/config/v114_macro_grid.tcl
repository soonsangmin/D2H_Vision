# Deterministic no-optimization grid for ALL SRAM macros. Tile area ~24x19mm.
# Avoids asking RTL macro placer to search 1,180 macro locations.
# Lock placements to preserve reproducibility. No fake or abstract memories.
set block [ord::get_db_block]
set macros {}
foreach inst [$block getInsts] {
    set master [$inst getMaster]
    set name [$master getName]
    if {[string match "sky130_sram_2kbyte_1rw1r_32x512_8" $name] ||
        [string match "sky130_sram_1kbyte_1rw1r_32x256_8" $name]} {
        lappend macros [$inst getName]
    }
}
set macros [lsort $macros]
puts "V114_MACRO_PLACER_TOTAL=[llength $macros]"
if {[llength $macros] != 1180} {
    error "V114 macro count mismatch before placement: [llength $macros] (expected 1180)"
}
set cols 32
set x_start 400.0
set y_start 400.0
set pitch_x 750.0
set pitch_y 500.0
set idx 0
foreach macro $macros {
    set col [expr {$idx % $cols}]
    set row [expr {$idx / $cols}]
    set x [expr {$x_start+$col*$pitch_x}]
    set y [expr {$y_start+$row*$pitch_y}]
    place_macro -macro_name $macro -location [list $x $y] -orientation R0
    incr idx
}
puts "V114_PLACED_AND_LOCKED=$idx (32-column SRAM grid)"

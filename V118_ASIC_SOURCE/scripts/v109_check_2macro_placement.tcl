# Invoked in ORFS docker after floorplan. Reject unplaced/overlapping macros.
read_db /workspace/output/v109_2macro/results/2_2_floorplan_macro.odb
set block [ord::get_db_block]
set dbu [$block getDbUnitsPerMicron]
set master "sky130_sram_2kbyte_1rw1r_32x512_8"
set boxes [list]
set count 0
foreach inst [$block getInsts] {
    if {[[$inst getMaster] getName] ne $master} {continue}
    incr count
    set name [$inst getName]
    set status [$inst getPlacementStatus]
    if {$status ne "FIRM" && $status ne "PLACED" && $status ne "LOCKED"} {
        error "V109 unplaced macro $name status=$status"
    }
    set box [$inst getBBox]
    set x0 [$box xMin]; set y0 [$box yMin]
    set x1 [$box xMax]; set y1 [$box yMax]
    if {$x0 < 40000 || $y0 < 40000 || $x1 > 1740000 || $y1 > 760000} {
        error "V109 macro outside CORE_AREA: $name bbox=$x0,$y0,$x1,$y1"
    }
    foreach old $boxes {
        lassign $old ox0 oy0 ox1 oy1
        if {$x0 < $ox1 && $x1 > $ox0 && $y0 < $oy1 && $y1 > $oy0} {
            error "V109 overlapping macro: $name"
        }
    }
    lappend boxes [list $x0 $y0 $x1 $y1]
    puts [format {V109_MACRO name=%s status=%s bbox_um=(%.2f,%.2f)-(%.2f,%.2f)} \
        $name $status [expr {double($x0)/$dbu}] [expr {double($y0)/$dbu}] \
        [expr {double($x1)/$dbu}] [expr {double($y1)/$dbu}]]
}
puts "V109_SRAM_MACRO_COUNT=$count"
if {$count != 2} {error "V109 expected 2 macros; got $count"}
puts "PASS: 2 SRAM macro placements, within core, non-overlapping. (Not DRC/LVS/GDS)"

# Usage: openroad -exit /workspace/scripts/v114_inspect_odb.tcl
set file "/workspace/output/v114_fullchip/results/1_synth.odb"
if {![file exists $file]} { puts "V114_SYNTH_ODB_MISSING"; exit 3 }
read_db $file
set db [ord::get_db]
set block [$db getChip]
set block [$block getBlock]
set n2 0
set n1 0
set nstd 0
foreach inst [$block getInsts] {
    set master [[$inst getMaster] getName]
    if {$master eq "sky130_sram_2kbyte_1rw1r_32x512_8"} {
        incr n2
    } elseif {$master eq "sky130_sram_1kbyte_1rw1r_32x256_8"} {
        incr n1
    } else {
        incr nstd
    }
}
puts "V114_POST_SYNTH_HANDSEG_2K=$n2"
puts "V114_POST_SYNTH_CNN_1K=$n1"
puts "V114_POST_SYNTH_OTHER_CELLS=$nstd"
if {$n2 != 1128 || $n1 != 52} {
    error "V114 macro count mismatch after synthesis: expected 1128 x 2K and 52 x 1K"
}
puts "V114_POST_SYNTH_MACROS_PASS"

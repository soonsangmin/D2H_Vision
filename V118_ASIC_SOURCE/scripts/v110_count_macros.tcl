# OpenROAD OpenDB audit, after ORFS synthesis only.
read_db /workspace/output/v110_handseg_8bank/results/1_synth.odb
set block [ord::get_db_block]
set expected {480 240 180 20 6 2 180 20}
set total 0
set by_bank {0 0 0 0 0 0 0 0}
set unclassified 0
set unknown_names {}
foreach inst [$block getInsts] {
    set master_name [[$inst getMaster] getName]
    if {$master_name ne "sky130_sram_2kbyte_1rw1r_32x512_8"} {
        continue
    }
    incr total
    set inst_name [$inst getName]
    if {[regexp {u_bank([0-7])} $inst_name _ bank]} {
        lset by_bank $bank [expr {[lindex $by_bank $bank] + 1}]
    } else {
        incr unclassified
        if {[llength $unknown_names] < 5} { lappend unknown_names $inst_name }
    }
}
puts "V110_SRAM_MACRO_COUNT=$total"
puts "V110_BANK_MACRO_COUNTS=$by_bank"
puts "V110_EXPECTED_BANK_COUNTS=$expected"
if {$total != 1128} { error "Expected 1128 physical SRAM instances, got $total" }
if {$unclassified != 0} { error "Bank hierarchy names unclassified ($unclassified): $unknown_names" }
if {$by_bank ne $expected} { error "Bank SRAM counts mismatch" }
puts "PASS: Full 8-bank HandSeg feature memory = 1128 physical SRAM macros in top OpenDB"
puts "NOTE: This is MEMORY SUBSYSTEM only, NOT end-to-end AI or GDS."

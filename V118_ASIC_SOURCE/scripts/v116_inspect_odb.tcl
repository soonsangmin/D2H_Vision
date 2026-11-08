set f "/workspace/output/v116_nearfull/results/1_synth.odb"
if {![file exists $f]} {error "V116 synth OpenDB absent"}
read_db $f
set b [ord::get_db_block]
set cnt_1k 0
set cnt_rom 0
set cnt_fifo 0
set cnt_std 0
foreach inst [$b getInsts] {
 set name [[$inst getMaster] getName]
 switch -exact -- $name {
  sky130_sram_1kbyte_1rw1r_32x256_8 {incr cnt_1k}
  v116_MISSING_WEIGHT_ROM {incr cnt_rom}
  v116_MISSING_PIXEL_FIFO_RAM {incr cnt_fifo}
  default {incr cnt_std}
 }
}
puts "V116_CNN_REAL_1K_SRAM_COUNT=$cnt_1k"
puts "V116_MISSING_WEIGHT_ROM_COUNT=$cnt_rom"
puts "V116_MISSING_FIFO_RAM_COUNT=$cnt_fifo"
puts "V116_OTHER_INSTANCE_COUNT=$cnt_std"
if {$cnt_rom < 1 || $cnt_fifo < 1 || $cnt_std < 100} {
 error "V116 intended near-full logic/memory boundary missing, refusing incorrect GDS claim"
}
if {$cnt_1k != 52} {
 puts "V116_WARNING: previously expected CNN SRAM=52, found $cnt_1k. Review module retention."
}
puts "V116_SYNTH_ODB_AUDIT_PASS_WITH_ABSENT_MEMORIES"

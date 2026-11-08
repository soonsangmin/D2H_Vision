# V117 near-full compute macro inspection. This is NOT signoff or equivalence.
set f "/workspace/output/v117_nearfull/results/1_synth.odb"
if {![file exists $f]} {error "V117 synthesis OpenDB not found"}
read_db $f
set block [ord::get_db_block]
set n_1k 0
set n_rom 0
set n_fifo 0
set n_row 0
set n_vec 0
set n_logic 0
foreach inst [$block getInsts] {
 set name [[$inst getMaster] getName]
 if {$name eq "sky130_sram_1kbyte_1rw1r_32x256_8"} {incr n_1k
 } elseif {$name eq "v116_MISSING_WEIGHT_ROM"} {incr n_rom
 } elseif {$name eq "v116_MISSING_PIXEL_FIFO_RAM"} {incr n_fifo
 } elseif {$name eq "v117_MISSING_ROW_RAM"} {incr n_row
 } elseif {[string match "v117_MISSING_VECTOR_RAM*" $name]} {incr n_vec
 } else {incr n_logic}
}
puts "V117_REAL_CNN_SRAM_MACROS=$n_1k"
puts "V117_NONFUNCTIONAL_WEIGHT_ROM=$n_rom"
puts "V117_NONFUNCTIONAL_PIXEL_FIFO=$n_fifo"
puts "V117_NONFUNCTIONAL_ROW_RAM=$n_row"
puts "V117_NONFUNCTIONAL_RESIDUAL_VECTOR_RAM=$n_vec"
puts "V117_OTHER_CELL_INSTANCES=$n_logic"
if {$n_rom < 1 || $n_fifo < 1 || $n_row < 1 || $n_vec < 1 || $n_logic < 100} {
 error "V117 failed: expected compute and memory boundaries not present in physical netlist"
}
if {$n_1k != 52} {puts "V117_WARNING_REAL_CNN_SRAM_NOT_52=$n_1k"}
puts "V117_ODB_MACRO_BOUNDARY_CHECK_PASS_WITH_NONFUNCTIONAL_STORAGE"

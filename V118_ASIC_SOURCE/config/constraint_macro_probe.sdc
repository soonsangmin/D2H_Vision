# Macro integration probe only: not full-chip IO signoff constraints.
create_clock -name core_clk -period 100.000 [get_ports clk_i]
set_input_delay -clock core_clk -max 5.000 [all_inputs -no_clocks]
set_input_delay -clock core_clk -min 0.000 [all_inputs -no_clocks]
set_output_delay -clock core_clk -max 5.000 [all_outputs]
set_output_delay -clock core_clk -min 0.000 [all_outputs]

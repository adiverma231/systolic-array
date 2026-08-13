# Stage 4 signoff constraints for the fixed N=8 OS macro.
create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.15 [get_clocks clk]

set_input_delay 0.75 -clock clk [get_ports {rst start load_a_en load_a_row load_a_col load_a_data load_b_en load_b_row load_b_col load_b_data result_row result_col}]
set_output_delay 0.75 -clock clk [all_outputs]

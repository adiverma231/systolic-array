# Stage 4 implementation constraints for the fixed N=8 OS macro.
# The nominal target is 100 MHz (10 ns period); signoff.sdc is intentionally
# separate so later closure work can tighten signoff margins independently.
create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.10 [get_clocks clk]

set_input_delay 0.50 -clock clk [get_ports {rst start load_a_en load_a_row load_a_col load_a_data load_b_en load_b_row load_b_col load_b_data result_row result_col}]
set_output_delay 0.50 -clock clk [all_outputs]

# Reset is synchronous in the RTL, so it remains a timed input.  The clock
# itself is excluded from the generic input-delay collection above.

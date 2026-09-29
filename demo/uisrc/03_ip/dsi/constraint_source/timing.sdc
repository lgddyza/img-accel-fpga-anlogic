create_clock -name {I_clk} -period 40.000 -waveform {0.000 20.000} [get_ports {I_clk}]
derive_pll_clocks
rename_clock -name {clk0} -source [get_ports {I_clk}] -master_clock {{I_clk}} [get_pins {u_pll/pll_inst.clkc[1]}]
rename_clock -name {clk1} -source [get_ports {I_clk}] -master_clock {{I_clk}} [get_pins {u_pll/pll_inst.clkc[2]}]
rename_clock -name {clk2} -source [get_ports {I_clk}] -master_clock {{I_clk}} [get_pins {u_pll/pll_inst.clkc[3]}]
rename_clock -name {clk3} -source [get_ports {I_clk}] -master_clock {{I_clk}} [get_pins {u_pll/pll_inst.clkc[4]}]
rename_clock -name {clk4} -source [get_ports {I_clk}] -master_clock {{I_clk}} [get_pins {u_pll/pll_inst.clkc[5]}]
set_clock_groups -exclusive -group [get_clocks {I_clk}] -group [get_clocks {clk0}] -group [get_clocks {clk1}] -group [get_clocks {clk2}] -group [get_clocks {clk3}] -group [get_clocks {clk4}]
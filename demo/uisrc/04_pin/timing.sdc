create_clock -name {sys_clk} -period 40.000 -waveform {0.000 20.000} [get_ports {I_sysclk_25m}]
create_clock -name {ddr_clk} -period 10.000 -waveform {0.000 5.000} [get_ports {I_ddr_clk}]

derive_clocks

rename_clock -name {S_clk_25m} [get_clocks {X_ui_pll/pll_inst.clkc[0]}]
rename_clock -name {S_clk_70m} [get_clocks {X_ui_pll/pll_inst.clkc[1]}]
rename_clock -name {S_clk}	 [get_clocks {X_ui_pll/pll_inst.clkc[2]}]
rename_clock -name {S_clk_x2} [get_clocks {X_ui_pll/pll_inst.clkc[3]}]
rename_clock -name {S_clk_x4} [get_clocks {X_ui_pll/pll_inst.clkc[4]}]
rename_clock -name {S_clk_x4_90d} [get_clocks {X_ui_pll/pll_inst.clkc[5]}]
rename_clock -name {S_lp_clk} [get_clocks {X_ui_pll/pll_inst.clkc[6]}]


set_clock_groups -exclusive -group [get_clocks {X_ui_ddr/dfi_clk}] -group [get_clocks {S_clk_25m}] -group [get_clocks {S_clk_70m}]  -group [get_clocks {S_clk}] -group [get_clocks {S_clk_x2}] -group [get_clocks {S_clk_x4}] -group [get_clocks {S_clk_x4_90d}] -group [get_clocks {S_lp_clk}]


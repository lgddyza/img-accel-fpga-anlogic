create_clock -name {sys_clk} -period 40.000 -waveform {0.000 20.000} [get_ports {I_sysclk_25m}]
create_clock -name {ddr_clk} -period 10.000 -waveform {0.000 5.000} [get_ports {I_ddr_clk}]
# demo ui_imx415_reg: SYS_MODE=0x09, 720 Mbps/lane DDR -> 360 MHz clock.
create_clock -name {mipi_hs_clk} -period 2.777 -waveform {0.000 1.3885} [get_ports {I_clk_hs_p}]

derive_clocks

rename_clock -name {S_clk_70m} [get_clocks {X_ui_pll/pll_inst.clkc[0]}]
rename_clock -name {S_clk_25m} [get_clocks {X_ui_pll/pll_inst.clkc[1]}]
rename_clock -name {S_clk}	 [get_clocks {X_ui_pll/pll_inst.clkc[2]}]
rename_clock -name {S_clk_x2} [get_clocks {X_ui_pll/pll_inst.clkc[3]}]
rename_clock -name {S_clk_x4} [get_clocks {X_ui_pll/pll_inst.clkc[4]}]
rename_clock -name {S_clk_x4_90d} [get_clocks {X_ui_pll/pll_inst.clkc[5]}]
rename_clock -name {S_lp_clk} [get_clocks {X_ui_pll/pll_inst.clkc[6]}]
rename_clock -name {pcie_core_src} [get_clocks {u_pcie_gray/u_sgdma_pll/pll_inst.clkc[0]}]
rename_clock -name {pcie_aux_clk} [get_clocks {u_pcie_gray/u_sgdma_pll/pll_inst.clkc[1]}]
rename_clock -name {jpeg_enc_clk} [get_clocks {u_pcie_gray/u_jpeg_clk_pll/pll_inst.clkc[0]}]
rename_clock -name {mipi_clk_180m} [get_clocks {X_mipi_dphy_rx_over_lvds_wrapper/u_rx_clk_gen/U_io_clk_div_0.clkdivout}]
rename_clock -name {mipi_clk_360m} [get_clocks {X_mipi_dphy_rx_over_lvds_wrapper/u_rx_clk_gen/U_io_clk_div_0.clkout}]
rename_clock -name {mipi_clk_90m} [get_clocks {X_mipi_dphy_rx_over_lvds_wrapper/u_rx_clk_gen/U_io_clk_div_1.clkdivout}]


# Independent sources: board 25 MHz, board DDR reference, forwarded MIPI,
# PCIe reference. Related PLL outputs remain timed together. The PCIe clock
# paths deliberately match the hierarchy used by the vendor SGDMA example;
# a short clock name returns an empty collection in TD.
set_clock_groups -asynchronous \
    -group [get_clocks {sys_clk S_clk_25m S_clk_70m S_clk S_clk_x2 S_clk_x4 S_clk_x4_90d S_lp_clk pcie_core_src pcie_aux_clk}] \
    -group [get_clocks {ddr_clk jpeg_enc_clk X_ui_ddr/dfi_clk X_ui_ddr/mcu_clk X_ui_ddr/ref_clk}] \
    -group [get_clocks {mipi_hs_clk mipi_clk_90m mipi_clk_180m mipi_clk_360m}] \
    -group [get_clocks {u_pcie_gray/u_sgdma_subsys/DEVICE_IS_PH1A$u_ph1a_if_ep/PH1A_PCIE_CORE_BLK$u_al_pcie_ip/pcie_user_clk u_pcie_gray/u_sgdma_subsys/DEVICE_IS_PH1A$u_ph1a_if_ep/PH1A_PCIE_CORE_BLK$u_al_pcie_ip/core_clk}]


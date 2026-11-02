# V2 independent forwarded clocks, not a muxed camera clock.
create_clock -name sys_clk -period 40.000 [get_ports I_sysclk_25m]
create_clock -name ddr_clk -period 10.000 [get_ports I_ddr_clk]
# Official dual-camera 37.125 MHz profile: 891 Mbps/lane, forwarded clock
# 445.5 MHz, matching the example in E:\FPGA\workspace\双路demo.
create_clock -name mipi_a -period 2.24467 [get_ports I_cam_a_clk_hs]
create_clock -name mipi_b -period 2.24467 [get_ports I_cam_b_clk_hs]
derive_clocks
rename_clock -name cfg_clk [get_clocks {X_ui_pll/pll_inst.clkc[1]}]
rename_clock -name lp_clk [get_clocks {X_ui_pll/pll_inst.clkc[0]}]
rename_clock -name pcie_core_src [get_clocks {u_pcie/u_sgdma_pll/pll_inst.clkc[0]}]
rename_clock -name pcie_aux [get_clocks {u_pcie/u_sgdma_pll/pll_inst.clkc[1]}]
rename_clock -name jpeg_enc [get_clocks {u_pcie/u_jpeg_clk_pll/pll_inst.clkc[0]}]
set_clock_groups -asynchronous \
    -group [get_clocks {sys_clk cfg_clk lp_clk pcie_core_src pcie_aux}] \
    -group [get_clocks {ddr_clk u_ddr/X_ui_ddr/dfi_clk u_ddr/X_ui_ddr/mcu_clk u_ddr/X_ui_ddr/ref_clk}] \
    -group [get_clocks {jpeg_enc}] \
    -group [get_clocks -include_generated_clocks {mipi_a}] \
    -group [get_clocks -include_generated_clocks {mipi_b}] \
    -group [get_clocks {u_pcie/u_sgdma_subsys/DEVICE_IS_PH1A$u_ph1a_if_ep/PH1A_PCIE_CORE_BLK$u_al_pcie_ip/pcie_user_clk u_pcie/u_sgdma_subsys/DEVICE_IS_PH1A$u_ph1a_if_ep/PH1A_PCIE_CORE_BLK$u_al_pcie_ip/core_clk}]

# Only cfg_clk -> the two named reset-synchronizer banks is asynchronous.
# The register selector survives hierarchy flattening (module input pins do not).
# cfg_clk reaches only their async reset pins; D inputs are constants/lp_clk stages.
# Preserve lp_clk stage-to-stage paths and all synchronizer-output recovery checks.
set_false_path -from [get_clocks cfg_clk] -to [get_regs {u_camera_a/u_ref_reset/stages*}]
set_false_path -from [get_clocks cfg_clk] -to [get_regs {u_camera_b/u_ref_reset/stages*}]

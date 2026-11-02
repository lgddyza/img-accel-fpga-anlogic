# Synthesis/resource check only. Does not place, route, generate or program a bit.
set project_root [file dirname [file dirname [file normalize [info script]]]]
cd $project_root
file mkdir build/dsi_resources
if {[catch {
    import_device ph1_90.db -package PH1A90SEG324 -speed 2
    open_project fpga_prj_jpeg.al -single_run
    load_run_param -run syn_1
    set_param flow qor_monitor off
    elaborate -top system_top
    read_adc -ip al_pcie_ip -file al_ip/PH1_LOGIC_PCIE.adc
    read_adc -ip ui_ddr -file uisrc/03_ip/al_ip/ui_ddr/ui_ddr.adc
    read_sdc -ip al_pcie_ip al_ip/PH1_LOGIC_PCIE.sdc
    read_sdc -ip ui_ddr uisrc/03_ip/al_ip/ui_ddr/ui_ddr.sdc
    read_adc uisrc/04_pin/fpga_pin.adc
    read_sdc uisrc/04_pin/timing.sdc
    optimize_rtl
    report_area -file build/dsi_resources/rtl.area
    optimize_gate -packarea build/dsi_resources/gate.area
    legalize_phy_inst
    export_db build/dsi_resources/gate.db
} message]} {
    puts "DSI_RESOURCE_CHECK_FAIL: $message"
    exit 1
}
puts "DSI_RESOURCE_CHECK_PASS"
exit

set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
set python {C:/Users/21093/AppData/Local/Programs/Python/Python312/python.exe}
file mkdir build/gray_demo
if {[catch {
    import_device ph1_90.db -package PH1A90SEG324 -speed 2
    open_project dual_imx415_gray_demo.al -single_run
    load_run_param -run syn_1
    set_param flow qor_monitor off
    set_param route post_route_opt high
    elaborate -top dual_imx415_top
    read_adc -ip al_pcie_ip -file al_ip/PH1_LOGIC_PCIE.adc
    read_adc -ip ui_ddr -file uisrc/03_ip/al_ip/ui_ddr/ui_ddr.adc
    read_sdc -ip al_pcie_ip al_ip/PH1_LOGIC_PCIE.sdc
    read_sdc -ip ui_ddr uisrc/03_ip/al_ip/ui_ddr/ui_ddr.sdc
    read_adc uisrc/04_pin/fpga_pin.adc
    read_sdc uisrc/04_pin/timing.sdc
    optimize_rtl
    report_area -file build/gray_demo/gate.area
    place
    report_area -io_info -file build/gray_demo/place.area
    route
    update_timing -mode final
    report_timing_summary -file build/gray_demo/route.timing
    report_timing_status -file build/gray_demo/route.ts
    check_timing -verbose -file build/gray_demo/check.timing
    bitgen -bit build/gray_demo/dual_imx415_gray_demo.bit
} message]} {
    puts "GRAY_DEMO_BUILD_FAIL: $message"
    exit 1
}
puts GRAY_DEMO_BUILD_COMPLETE
exit

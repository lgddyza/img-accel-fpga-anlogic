set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
file mkdir build/stream_fix
if {[catch {
    import_device ph1_90.db -package PH1A90SEG324 -speed 2
    open_project dual_imx415_gray_demo.al -single_run
    load_run_param -run syn_1
    set_param flow qor_monitor off
    elaborate -top dual_imx415_top
    read_adc -ip al_pcie_ip -file al_ip/PH1_LOGIC_PCIE.adc
    read_adc -ip ui_ddr -file uisrc/03_ip/al_ip/ui_ddr/ui_ddr.adc
    read_sdc -ip al_pcie_ip al_ip/PH1_LOGIC_PCIE.sdc
    read_sdc -ip ui_ddr uisrc/03_ip/al_ip/ui_ddr/ui_ddr.sdc
    read_adc uisrc/04_pin/fpga_pin.adc
    read_sdc uisrc/04_pin/timing.sdc
    optimize_rtl
    report_area -file build/stream_fix/gate.area
    export_db build/stream_fix/gate.db
    optimize_gate -packarea build/stream_fix/pack.area
    report_area -file build/stream_fix/mapped.area
} message]} {
    puts "STREAM_FIX_SYNTHESIS_FAIL: $message"
    exit 1
}
puts STREAM_FIX_SYNTHESIS_PASS
exit

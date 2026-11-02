# Full-design physical probe using the production default 37.125 MHz profile.
# No bit generation or programming.
# Keep the recorded resource inputs unchanged during this run.
set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
set python {C:/Users/21093/AppData/Local/Programs/Python/Python312/python.exe}
if {[info exists env(V2_PYTHON)]} {set python $env(V2_PYTHON)}
file mkdir build/full_physical
puts [exec $python tools/record_build_inputs.py --verify]
file copy -force build/resource_inputs.json build/full_physical/resource_inputs.json
file copy -force [info script] build/full_physical/run_script.tcl
set f [open rtl/dual_imx415_top.v r];set source [read $f];close $f
set source [string map {dual_imx415_top dual_resource_probe} $source]
set f [open build/dual_resource_probe.v r];set existing [read $f];close $f
if {[string trim $source] ne [string trim $existing]} {error {Resource probe source differs; regenerate with check_resources.tcl first.}}
if {[catch {
    import_device ph1_90.db -package PH1A90SEG324 -speed 2
    open_project dual_resource_probe.al -single_run
    load_run_param -run syn_1
    set_param flow qor_monitor off
    elaborate -top dual_resource_probe
    read_adc -ip al_pcie_ip -file al_ip/PH1_LOGIC_PCIE.adc
    read_adc -ip ui_ddr -file uisrc/03_ip/al_ip/ui_ddr/ui_ddr.adc
    read_sdc -ip al_pcie_ip al_ip/PH1_LOGIC_PCIE.sdc
    read_sdc -ip ui_ddr uisrc/03_ip/al_ip/ui_ddr/ui_ddr.sdc
    read_adc uisrc/04_pin/fpga_pin.adc
    read_sdc uisrc/04_pin/timing.sdc
    optimize_rtl
    optimize_gate -packarea build/full_physical/pack.area
    export_db build/full_physical/gate.db
    place
    report_area -io_info -file build/full_physical/place.area
    report_clock_utilization -file build/full_physical/clocks.txt
    export_db build/full_physical/place.db
    route
    report_area -io_info -file build/full_physical/route.area
    update_timing -mode final
    report_timing_summary -file build/full_physical/route.timing
    report_timing_status -file build/full_physical/route.ts
    check_timing -verbose -file build/full_physical/check.timing
    report_route_status -file build/full_physical/route_status.txt
    export_db build/full_physical/route.db
    puts [exec $python tools/record_build_inputs.py --verify]
} message]} {
    puts "V2_FULL_PHYSICAL_FAIL: $message"
    exit 1
}
puts V2_FULL_PHYSICAL_FLOW_COMPLETE
puts {Inspect timing/route/unconstrained reports separately; no bit generated.}
exit

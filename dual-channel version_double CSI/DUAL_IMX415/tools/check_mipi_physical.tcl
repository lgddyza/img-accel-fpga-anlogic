# Independent, non-programmable two-RX placement/connectivity probe.
# Excludes DDR/PCIe/ISP: success does not establish full-system timing closure.
set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
set f [open dual_imx415.al r]
set project [read $f]
close $f
set project [string map {<Name>dual_imx415</Name> <Name>mipi_physical_probe</Name> >dual_imx415_top< >mipi_physical_probe<} $project]
set entry {            <File Path="sim/mipi_physical_probe.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="999"/>
                </FileInfo>
            </File>
        </Verilog>}
set project [string map [list {        </Verilog>} $entry] $project]
set f [open mipi_physical_probe.al w]; puts $f $project; close $f
set f [open uisrc/04_pin/fpga_pin.adc r];set pins [read $f];close $f
set f [open build/mipi_physical.adc w]
foreach line [split $pins \n] {
    if {[string match {*cam_*} $line] || [string match {*I_sysclk_25m*} $line]} {puts $f $line}
}
close $f
set f [open build/mipi_physical.sdc w]
puts $f {create_clock -name sys_clk -period 40.000 [get_ports I_sysclk_25m]
# Official IMX415 SYS_MODE=5 profile: 891 Mbps/lane, forwarded clock 445.5 MHz.
create_clock -name mipi_a -period 2.24467 [get_ports I_cam_a_clk_hs]
create_clock -name mipi_b -period 2.24467 [get_ports I_cam_b_clk_hs]
derive_clocks}
close $f
if {[catch {
    import_device ph1_90.db -package PH1A90SEG324 -speed 2
    open_project mipi_physical_probe.al -single_run
    load_run_param -run syn_1
    set_param flow qor_monitor off
    elaborate -top mipi_physical_probe
    read_adc build/mipi_physical.adc
    read_sdc build/mipi_physical.sdc
    optimize_rtl
    optimize_gate -packarea build/mipi_physical_pack.area
    export_db build/mipi_physical_gate.db
    place
    report_area -io_info -file build/mipi_physical_place.area
    report_clock_utilization -file build/mipi_physical_clocks.txt
    export_db build/mipi_physical_place.db
    route
    update_timing -mode final
    report_timing_summary -file build/mipi_physical_route.timing
    report_timing_status -file build/mipi_physical_route.ts
    report_route_status -file build/mipi_physical_route_status.txt
    export_db build/mipi_physical_route.db
} message]} {
    puts "V2_MIPI_PHYSICAL_FAIL: $message"
    exit 1
}
puts V2_MIPI_PHYSICAL_CONNECTIVITY_PASS
puts {No bit generated; probe excludes DDR/PCIe and is not a timing-closure claim.}
exit

# Resource estimate using the production default 37.125 MHz camera profile.
# Both RX pipelines must remain live; this does not prove physical timing.
set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
set python {C:/Users/21093/AppData/Local/Programs/Python/Python312/python.exe}
if {[info exists env(V2_PYTHON)]} {set python $env(V2_PYTHON)}
puts [exec $python tools/record_build_inputs.py]
set f [open rtl/dual_imx415_top.v r]
set source [read $f]
close $f
set source [string map {dual_imx415_top dual_resource_probe} $source]
set f [open build/dual_resource_probe.v w]
puts $f $source
close $f
set f [open dual_imx415.al r]
set project [read $f]
close $f
set project [string map {<Name>dual_imx415</Name> <Name>dual_resource_probe</Name> >dual_imx415_top< >dual_resource_probe<} $project]
set entry {            <File Path="build/dual_resource_probe.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="999"/>
                </FileInfo>
            </File>
        </Verilog>}
set project [string map [list {        </Verilog>} $entry] $project]
set f [open dual_resource_probe.al w]
puts $f $project
close $f
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
    report_area -file build/v2_rtl.area
    optimize_gate -packarea build/v2_pack.area
    report_area -file build/v2_gate.area
    puts [exec $python tools/record_build_inputs.py --verify]
} message]} {
    puts "V2_RESOURCE_FAIL: $message"
    exit 1
}
puts V2_RESOURCE_PASS
exit

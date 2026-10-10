# Full validation of the RTL timing fix, with separate reports and bitstream.
set project_root [file dirname [file dirname [file normalize [info script]]]]
set result_dir [file join $project_root tools timingfix_rtl_20261009]
file mkdir $result_dir
set prefix [file join $result_dir ehp1]
if {[catch {
cd $project_root
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
insert_debugger
optimize_rtl
report_area -file ${prefix}_synth.area
optimize_gate -packarea ${prefix}_gate.area
legalize_phy_inst
update_timing
report_timing_status -file ${prefix}_gate.ts
report_timing_summary -file ${prefix}_gate.timing
export_db ${prefix}_gate.db
set_param route post_route_opt high
set_param route postrt_opt_extra_round 4
place
update_timing -mode manhattan
report_area -io_info -file ${prefix}_place.area
report_timing_status -file ${prefix}_place.ts
export_db ${prefix}_place.db
route
set_param route hold_fix_iteration 10
fix_hold
update_timing -mode final
report_area -io_info -file ${prefix}_route.area
report_timing_status -file ${prefix}_route.ts
report_timing_summary -file ${prefix}_route.timing
check_timing -verbose -file ${prefix}_check.timing
export_db ${prefix}_route.db
set status_handle [open ${prefix}_route.ts r]
set status_text [read $status_handle]
close $status_handle
if {![regexp {SWNS: ([+-]?[0-9.]+)ns} $status_text unused setup_wns] ||
    ![regexp {HWNS: ([+-]?[0-9.]+)ns} $status_text unused hold_wns]} {
    error "Could not parse final timing status"
}
puts "TIMING_RTLFIX_RESULT setup=${setup_wns}ns hold=${hold_wns}ns"
if {$setup_wns >= 0 && $hold_wns >= 0} {
    bitgen -bit ${prefix}_candidate.bit
    puts "TIMING_RTLFIX_CLOSED"
} else {
    puts "TIMING_RTLFIX_NOT_CLOSED"
}
} message]} {
    puts "TIMING_RTLFIX_FAIL: $message"
    exit 1
}
exit

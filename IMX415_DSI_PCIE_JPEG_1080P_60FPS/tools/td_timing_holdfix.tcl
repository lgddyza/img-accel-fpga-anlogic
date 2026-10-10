# Repair hold on the user's 22:19 routed implementation; keep GUI outputs intact.
set project_root [file dirname [file dirname [file normalize [info script]]]]
set result_dir [file join $project_root tools timingfix_hold_20261009_2219]
file mkdir $result_dir
set prefix [file join $result_dir ehp1]
set td_hold_input_checkpoint [file join $result_dir input_route.db]
if {[catch {
cd [file join $project_root fpga_prj_jpeg_Runs phy_1]
if {![file exists $td_hold_input_checkpoint]} {
    file copy fpga_prj_jpeg_pr.db $td_hold_input_checkpoint
    file copy final_timing.rpt [file join $result_dir input_final_timing.rpt]
    file copy fpga_prj_jpeg.bit [file join $result_dir input.bit]
    file copy fpga_prj_jpeg_phy.area [file join $result_dir input.area]
}
import_device ph1_90.db -package PH1A90SEG324 -speed 2
import_db ../../tools/timingfix_hold_20261009_2219/input_route.db
set_param flow qor_monitor off
update_timing -mode final
report_timing_status -file ${prefix}_before.ts
set_param route hold_fix_iteration 10
fix_hold
update_timing -mode final
report_area -io_info -file ${prefix}_route.area
report_timing_status -file ${prefix}_route.ts
report_timing_summary -file ${prefix}_route.timing
check_timing -verbose -file ${prefix}_check.timing
# TD prints the DRC results to its run log for this mode.
report_route_status -drc
export_db ${prefix}_route.db
set status_handle [open ${prefix}_route.ts r]
set status_text [read $status_handle]
close $status_handle
if {![regexp {SWNS: ([+-]?[0-9.]+)ns} $status_text unused setup_wns] ||
    ![regexp {HWNS: ([+-]?[0-9.]+)ns} $status_text unused hold_wns]} {
    error "Could not parse final timing status"
}
puts "TIMING_HOLDFIX_RESULT setup=${setup_wns}ns hold=${hold_wns}ns"
if {$setup_wns >= 0 && $hold_wns >= 0} {
    bitgen -bit ${prefix}_candidate.bit
    puts "TIMING_HOLDFIX_CLOSED"
} else {
    puts "TIMING_HOLDFIX_NOT_CLOSED"
}
} message]} {
    puts "TIMING_HOLDFIX_FAIL: $message"
    exit 1
}
exit

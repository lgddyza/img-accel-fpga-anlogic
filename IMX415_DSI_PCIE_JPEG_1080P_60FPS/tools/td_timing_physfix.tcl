# Preserve the GUI run; optimize its routed database into separate artifacts.
set project_root [file dirname [file dirname [file normalize [info script]]]]
set result_dir [file join $project_root tools timingfix_phys_20261009]
file mkdir $result_dir
set prefix [file join $result_dir ehp1]
if {[catch {
cd [file join $project_root fpga_prj_jpeg_Runs phy_1]
import_device ph1_90.db -package PH1A90SEG324 -speed 2
import_db fpga_prj_jpeg_pr.db
set_param flow qor_monitor off
set_param route post_route_opt high
set_param route postrt_opt_extra_round 4
phys_opt -post_route -effort high
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
puts "TIMING_PHYSFIX_RESULT setup=${setup_wns}ns hold=${hold_wns}ns"
if {$setup_wns >= 0 && $hold_wns >= 0} {
    bitgen -bit ${prefix}_candidate.bit
    puts "TIMING_PHYSFIX_CLOSED"
} else {
    puts "TIMING_PHYSFIX_NOT_CLOSED"
}
} message]} {
    puts "TIMING_PHYSFIX_FAIL: $message"
    exit 1
}
exit

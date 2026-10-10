# Resume final validation/bit generation from the saved hold-fixed database.
set project_root [file dirname [file dirname [file normalize [info script]]]]
set prefix [file join $project_root tools timingfix_hold_20261009_2219 ehp1]
if {[catch {
cd [file join $project_root fpga_prj_jpeg_Runs phy_1]
import_device ph1_90.db -package PH1A90SEG324 -speed 2
import_db ../../tools/timingfix_hold_20261009_2219/ehp1_route.db
set_param flow qor_monitor off
update_timing -mode final
report_timing_status -file ${prefix}_reloaded.ts
set status_handle [open ${prefix}_reloaded.ts r]
set status_text [read $status_handle]
close $status_handle
if {![regexp {SWNS: ([+-]?[0-9.]+)ns} $status_text unused setup_wns] ||
    ![regexp {HWNS: ([+-]?[0-9.]+)ns} $status_text unused hold_wns]} {
    error "Could not parse reloaded timing status"
}
puts "TIMING_HOLDFIX_RELOADED setup=${setup_wns}ns hold=${hold_wns}ns"
if {$setup_wns < 0 || $hold_wns < 0} {
    error "Reloaded database does not meet setup/hold timing"
}
bitgen -bit ${prefix}_candidate.bit
puts "TIMING_HOLDFIX_CLOSED"
} message]} {
    puts "TIMING_HOLDFIX_BITGEN_FAIL: $message"
    exit 1
}
exit

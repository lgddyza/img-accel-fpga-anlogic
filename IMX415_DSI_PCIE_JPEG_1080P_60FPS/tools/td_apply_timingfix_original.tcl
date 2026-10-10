# Restore the verified hold-fixed route as the original project's active result.
# Back up phy_1 and best_result before running this script.
set project_root [file dirname [file dirname [file normalize [info script]]]]
if {[catch {
cd $project_root
import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project fpga_prj_jpeg.al -single_run -noanalyze
load_run_param -run phy_1
cd [file join $project_root fpga_prj_jpeg_Runs phy_1]
import_db ../../tools/timingfix_hold_20261009_2219/ehp1_route.db
set_param flow qor_monitor off
update_timing -mode final
report_timing_status -file ../../tools/timingfix_hold_20261009_2219/ehp1_adopt_check.ts
set timing_apply_handle [open ../../tools/timingfix_hold_20261009_2219/ehp1_adopt_check.ts r]
set timing_apply_status [read $timing_apply_handle]
close $timing_apply_handle
if {![regexp {SWNS: ([+-]?[0-9.]+)ns} $timing_apply_status unused setup_wns] ||
    ![regexp {HWNS: ([+-]?[0-9.]+)ns} $timing_apply_status unused hold_wns]} {
    error "Could not parse final timing before adoption"
}
if {$setup_wns < 0 || $hold_wns < 0} {
    error "Refusing to adopt a database with setup/hold violations"
}
report_timing_status -file fpga_prj_jpeg_phy.ts
report_timing_summary -file fpga_prj_jpeg_pr.timing
report_timing_summary -file final_timing.rpt
report_timing_exception -file fpga_prj_jpeg_exception.timing
check_timing -verbose -file fpga_prj_jpeg_chk.timing
report_area -io_info -file fpga_prj_jpeg_phy.area
report_clock_utilization -file route_clock_utilization.txt
report_qor -step route -file route.qor
flow_status -file route_flow.status
export_db fpga_prj_jpeg_pr.db
set_param bitgen compress on
bitgen -bit fpga_prj_jpeg.bit
setup_debugger -prj fpga_prj_jpeg
export_bitgen_param -file .bitgen_param.f
file copy -force fpga_prj_jpeg_phy.ts cw/fpga_prj_jpeg_phy.ts
foreach timing_apply_name {
    fpga_prj_jpeg.bit fpga_prj_jpeg_compress.bit fpga_prj_jpeg_inst.bid
    fpga_prj_jpeg_phy.ts fpga_prj_jpeg_place.ts
} {
    file copy -force $timing_apply_name [file join .. best_result $timing_apply_name]
}
file mtime .opt_route.end.f [clock seconds]
file mtime .bitgen.end.f [clock seconds]
puts "TIMING_ORIGINAL_UPDATED setup=${setup_wns}ns hold=${hold_wns}ns"
} message]} {
    puts "TIMING_ORIGINAL_UPDATE_FAIL: $message"
    exit 1
}
exit

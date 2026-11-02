# Extra physical optimization of the complete routed design. No RTL/clock change.
set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
set python {C:/Users/21093/AppData/Local/Programs/Python/Python312/python.exe}
puts [exec $python tools/verify_hsfix.py]
file mkdir build/rtl_hsfix_final_polish
file copy -force build/rtl_hsfix/inputs.json build/rtl_hsfix_final_polish/inputs.json
file copy -force [info script] build/rtl_hsfix_final_polish/run_script.tcl
if {[catch {
 import_device ph1_90.db -package PH1A90SEG324 -speed 2
 import_db build/rtl_hsfix/route.db
 update_timing -mode final
 phys_opt -post_route -effort high
 fix_hold
 update_timing -mode final
 report_area -io_info -file build/rtl_hsfix_final_polish/route.area
 report_timing_summary -file build/rtl_hsfix_final_polish/route.timing
 report_timing_status -file build/rtl_hsfix_final_polish/route.ts
 check_timing -verbose -file build/rtl_hsfix_final_polish/check.timing
 report_route_status -drc -file build/rtl_hsfix_final_polish/route_status.txt
 export_db build/rtl_hsfix_final_polish/route.db
 puts [exec $python tools/verify_hsfix.py]
} message]} {
 puts "HSFIX_POLISH_FAIL: $message"
 exit 1
}
puts HSFIX_POLISH_FLOW_COMPLETE
exit


# Additional physical optimization from the completed managed OBS1 route.
# Keep the original run and its negative timing report intact.
set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
set python {C:/Users/21093/AppData/Local/Programs/Python/Python312/python.exe}
puts [exec $python tools/record_build_inputs.py --verify]
file mkdir build/obs1_polish
if {[catch {
    import_device ph1_90.db -package PH1A90SEG324 -speed 2
    import_db dual_imx415_gray_demo_Runs/phy_1/dual_imx415_gray_demo_pr.db
    set_param route postrt_opt_extra_round 4
    update_timing -mode final
    phys_opt -post_route -effort high
    fix_hold
    update_timing -mode final
    report_area -io_info -file build/obs1_polish/route.area
    report_timing_summary -file build/obs1_polish/route.timing
    report_timing_status -file build/obs1_polish/route.ts
    check_timing -verbose -file build/obs1_polish/check.timing
    report_route_status -drc -file build/obs1_polish/route_status.txt
    export_db build/obs1_polish/route.db
    puts [exec $python tools/record_build_inputs.py --verify]
    set handle [open build/obs1_polish/route.ts r]
    set timing [read $handle]
    close $handle
    foreach key {SWNS STNS HWNS HTNS} {
        if {![regexp "$key: (-?\[0-9.\]+)ns" $timing unused value] || $value < 0} {
            error "Unclosed routed timing: $timing"
        }
    }
    set_param bitgen compress on
    bitgen -bit build/obs1_polish/dual_imx415_OBS1_compress.bit
} message]} {
    puts "OBS1_POLISH_FAIL: $message"
    exit 1
}
puts OBS1_POLISH_COMPLETE_NO_PROGRAMMING
exit

# Complete post-fix production design. No bit is generated or programmed.
set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
set python {C:/Users/21093/AppData/Local/Programs/Python/Python312/python.exe}
file mkdir build/rtl_hsfix
puts [exec $python tools/verify_hsfix.py --record]
if {[catch {
 import_device ph1_90.db -package PH1A90SEG324 -speed 2
 open_project dual_imx415_hsfix.al -single_run
 load_run_param -run syn_1
 set_param flow qor_monitor off
 set_param route post_route_opt high
 elaborate -top dual_imx415_top
 read_adc -ip al_pcie_ip -file al_ip/PH1_LOGIC_PCIE.adc
 read_adc -ip ui_ddr -file uisrc/03_ip/al_ip/ui_ddr/ui_ddr.adc
 read_sdc -ip al_pcie_ip al_ip/PH1_LOGIC_PCIE.sdc
 read_sdc -ip ui_ddr uisrc/03_ip/al_ip/ui_ddr/ui_ddr.sdc
 read_adc uisrc/04_pin/fpga_pin.adc
 read_sdc uisrc/04_pin/timing.sdc
 optimize_rtl
 optimize_gate -packarea build/rtl_hsfix/pack.area
 report_area -file build/rtl_hsfix/gate.area
 export_db build/rtl_hsfix/gate.db
 place
 report_area -io_info -file build/rtl_hsfix/place.area
 export_db build/rtl_hsfix/place.db
 route
 report_area -io_info -file build/rtl_hsfix/route.area
 update_timing -mode final
 report_timing_summary -file build/rtl_hsfix/route.timing
 report_timing_status -file build/rtl_hsfix/route.ts
 check_timing -verbose -file build/rtl_hsfix/check.timing
 report_route_status -file build/rtl_hsfix/route_status.txt
 export_db build/rtl_hsfix/route.db
 puts [exec $python tools/verify_hsfix.py]
} message]} {
 puts "HSFIX_PHYSICAL_FAIL: $message"
 exit 1
}
puts HSFIX_PHYSICAL_FLOW_COMPLETE
puts {Inspect timing and route status separately. No programming performed.}
exit

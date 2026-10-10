# Exercise the failing GUI manifest; export candidate reports/databases separately.
set project_root [file dirname [file dirname [file normalize [info script]]]]
set report_prefix [file join $project_root tools ehp1_gui_fix]
if {[catch {
cd [file join $project_root fpga_prj_jpeg_Runs syn_1]
import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project fpga_prj_jpeg.prj
elaborate -top system_top
puts "EHP1_GUI_ELABORATE_PASS"
read_adc -ip al_pcie_ip -file ../../al_ip/PH1_LOGIC_PCIE.adc
read_adc -ip ui_ddr -file ../../uisrc/03_ip/al_ip/ui_ddr/ui_ddr.adc
read_sdc -ip al_pcie_ip ../../al_ip/PH1_LOGIC_PCIE.sdc
read_sdc -ip ui_ddr ../../uisrc/03_ip/al_ip/ui_ddr/ui_ddr.sdc
read_adc ../../uisrc/04_pin/fpga_pin.adc
read_sdc ../../uisrc/04_pin/timing.sdc
optimize_rtl
report_area -file ${report_prefix}_synth.area
optimize_gate -packarea ${report_prefix}_gate.area
export_db ${report_prefix}_gate.db
legalize_phy_inst
update_timing
report_area -io_info -file ${report_prefix}_legal.area
report_timing_status -file ${report_prefix}.ts
report_timing_summary -file ${report_prefix}.timing
} message]} {
    puts "EHP1_GUI_SYNTH_FAIL: $message"
    exit 1
}
puts "EHP1_GUI_SYNTH_PASS"
exit

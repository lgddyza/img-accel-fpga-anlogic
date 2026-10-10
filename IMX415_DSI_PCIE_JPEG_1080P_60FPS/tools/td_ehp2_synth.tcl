# Isolated reports for shared K3 blackhat gain1 and post-enhancement CLAHE.
set project_root [file dirname [file dirname [file normalize [info script]]]]
set prefix [file join $project_root tools ehp2]
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
optimize_rtl
report_area -file ${prefix}_synth.area
optimize_gate -packarea ${prefix}_gate.area
export_db ${prefix}_gate.db
legalize_phy_inst
update_timing
report_area -io_info -file ${prefix}_legal.area
report_timing_status -file ${prefix}_gate.ts
report_timing_summary -file ${prefix}_gate.timing
} message]} {
    puts "EHP2_SYNTH_FAIL: $message"
    exit 1
}
puts "EHP2_SYNTH_PASS"
exit

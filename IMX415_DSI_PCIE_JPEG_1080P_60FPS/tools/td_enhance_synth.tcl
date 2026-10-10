# Read the active project; write only isolated candidate reports.
if {[catch {
import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project fpga_prj_jpeg.al -single_run
load_run_param -run syn_1
elaborate -top system_top
read_adc -ip al_pcie_ip -file al_ip/PH1_LOGIC_PCIE.adc
read_adc -ip ui_ddr -file uisrc/03_ip/al_ip/ui_ddr/ui_ddr.adc
read_sdc -ip al_pcie_ip al_ip/PH1_LOGIC_PCIE.sdc
read_sdc -ip ui_ddr uisrc/03_ip/al_ip/ui_ddr/ui_ddr.sdc
read_adc uisrc/04_pin/fpga_pin.adc
read_sdc uisrc/04_pin/timing.sdc
optimize_rtl
report_area -file tools/ehp1_synth.area
optimize_gate -packarea tools/ehp1_gate.area
export_db tools/ehp1_gate.db
legalize_phy_inst
update_timing
report_area -io_info -file tools/ehp1_gate_legal.area
report_timing_status -file tools/ehp1_gate.ts
report_timing_summary -file tools/ehp1_gate.timing
} message]} {
    puts "EHP1_SYNTH_FAIL: $message"
    exit 1
}
puts "EHP1_SYNTH_PASS"
exit

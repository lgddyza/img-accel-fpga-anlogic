# Run with td_commands_prompt.exe from the project directory.
# Candidate output is isolated under tools/; best_result is never overwritten.
import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project fpga_prj.al -single_run
load_run_param -run syn_1
elaborate -top system_top
read_adc -ip al_pcie_ip -file al_ip/PH1_LOGIC_PCIE.adc
read_adc -ip ui_ddr -file uisrc/03_ip/al_ip/ui_ddr/ui_ddr.adc
read_sdc -ip al_pcie_ip al_ip/PH1_LOGIC_PCIE.sdc
read_sdc -ip ui_ddr uisrc/03_ip/al_ip/ui_ddr/ui_ddr.sdc
read_adc uisrc/04_pin/fpga_pin.adc
read_sdc uisrc/04_pin/timing.sdc
optimize_rtl
optimize_gate -packarea tools/preproc_histfix_gate.area
legalize_phy_inst
update_timing
place
update_timing -mode manhattan
report_area -io_info -file tools/preproc_histfix_place.area
route
update_timing -mode final
report_area -io_info -file tools/preproc_histfix_route.area
report_timing_status -file tools/preproc_histfix_route.ts
report_timing_summary -file tools/preproc_histfix_route.timing
check_timing -verbose -file tools/preproc_histfix_route_chk.timing
bitgen -bit tools/preproc_histfix_candidate.bit
puts "PREPROC_HISTFIX_ROUTE_PASS"
exit

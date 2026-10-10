# Fast recheck of the isolated synthesized database; no bit generation.
if {[catch {
import_device ph1_90.db -package PH1A90SEG324 -speed 2
import_db tools/ehp1_gate.db
legalize_phy_inst
update_timing
report_area -io_info -file tools/ehp1_gate_legal.area
report_timing_status -file tools/ehp1_gate.ts
report_timing_summary -file tools/ehp1_gate.timing
} message]} {
    puts "EHP1_GATE_CHECK_FAIL: $message"
    exit 1
}
puts "EHP1_GATE_CHECK_PASS"
exit

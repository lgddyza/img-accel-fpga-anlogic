# Run in the TD GUI Tcl console so its in-memory project is updated too.
set repair_root [file dirname [file dirname [file normalize [info script]]]]
set repair_pwd [pwd]
cd $repair_root
if {[catch {add_files rtl/v2_ddr_reset_guard.v -analyze} repair_message]} {
    cd $repair_pwd
    error "TD_REGISTRATION_REPAIR_FAIL: $repair_message"
}
cd $repair_pwd
puts TD_REGISTRATION_REPAIR_PASS

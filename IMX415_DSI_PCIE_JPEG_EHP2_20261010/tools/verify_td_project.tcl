# TD dependency/elaboration check only; no synthesis, route or bit generation.
set project_root [file dirname [file dirname [file normalize [info script]]]]
set work [file join $project_root build td_verify]
file mkdir $work
cd $project_root
if {[catch {
    import_device ph1_90.db -package PH1A90SEG324 -speed 2
    open_project fpga_prj_jpeg.al -single_run
    load_run_param -run syn_1
    set_param flow qor_monitor off
    elaborate -top system_top
} message]} {
    puts "EHP2_CLEAN_ELABORATE_FAIL: $message"
    exit 1
}
puts "EHP2_CLEAN_ELABORATE_PASS"
exit

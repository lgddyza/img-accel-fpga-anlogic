set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
if {[catch {
    import_device ph1_90.db -package PH1A90SEG324 -speed 2
    open_project dual_imx415_gray_demo.al -single_run
    load_run_param -run syn_1
    set_param flow qor_monitor off
    elaborate -top dual_imx415_top
} message]} {
    puts "GRAY_DEMO_ELABORATE_FAIL: $message"
    exit 1
}
puts GRAY_DEMO_ELABORATE_PASS
exit

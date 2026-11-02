set project_root [file dirname [file dirname [file normalize [info script]]]]
cd $project_root
if {[catch {
    if {[file exists build/dsi_gamma_micro_final/dsi_gamma_resource.al]} {
        import_device ph1_90.db -package PH1A90SEG324 -speed 2
        open_project build/dsi_gamma_micro_final/dsi_gamma_resource.al
    } else {
        create_project dsi_gamma_resource build/dsi_gamma_micro_final -family ph1 -device PH1A90SEG324 -speed 2
        add_files {../../uisrc/03_ip/ui_isp/ui_isp_top.v ../../sim/dsi_gamma_resource_top.v}
        top_module dsi_gamma_resource_top
    }
    set_param -run syn_1 flow qor_monitor off
    reset_runs syn_1
    launch_runs syn_1
    wait_run syn_1 -quiet
} message]} {
    puts "DSI_GAMMA_RESOURCE_CHECK_FAIL: $message"
    exit 1
}
puts "DSI_GAMMA_RESOURCE_CHECK_PASS"
exit

# Source-reading smoke check only. No optimize_rtl, gate mapping, or bitgen.
import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project fpga_prj_jpeg.al -single_run
load_run_param -run syn_1
elaborate -top system_top
puts "JPEG_PROJECT_ELABORATE_PASS"
exit

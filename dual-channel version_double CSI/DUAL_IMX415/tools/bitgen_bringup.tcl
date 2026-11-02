# Connectivity trial from the last completed implementation. No optimization
# and no programming. This database predates the JPEG elastic output register.
set root [file dirname [file dirname [file normalize [info script]]]]
cd $root
file mkdir release/bringup_20261023
if {[catch {
 import_device ph1_90.db -package PH1A90SEG324 -speed 2
 import_db build/before_jpeg_output_pipeline/polish/route.db
 commit_param -step bitgen
 set_param bitgen compress on
 bitgen -bit release/bringup_20261023/dual_imx415_hsfix_bringup.bit
} message]} {
 puts "BRINGUP_BITGEN_FAIL: $message"
 exit 1
}
puts BRINGUP_BITGEN_COMPLETE_NO_PROGRAMMING
exit

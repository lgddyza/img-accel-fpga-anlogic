# Execute in the PRF1 GUI project session, then save/reload through TD.
set prf_root [file dirname [file dirname [file normalize [info script]]]]
foreach prf_file {uisrc/01_rtl/gray_gauss4.v uisrc/01_rtl/gray_preprocess4.v} {
    add_files [file join $prf_root $prf_file] -analyze
}
set_strategy -run phy_1 TimingHigh
puts PRF1_SOURCE_REGISTRATION_COMPLETE_SAVE_AND_RELOAD_REQUIRED

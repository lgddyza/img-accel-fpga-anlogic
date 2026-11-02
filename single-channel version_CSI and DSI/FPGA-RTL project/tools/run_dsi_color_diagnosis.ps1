param(
    [string]$IcarusBin = 'E:\FPGA\workspace\.tools\iverilog\bin',
    [switch]$FullFrame
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$buildDir = Join-Path $projectRoot 'build\dsi_color_diagnosis'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
Push-Location $projectRoot
try {
    & 'C:\Users\21093\AppData\Local\Programs\Python\Python312\python.exe' tools/make_legacy_sim.py
    if ($LASTEXITCODE -ne 0) { throw 'Reference generation failed' }
    $ispFiles = Get-ChildItem 'uisrc\03_ip\ui_isp' -Filter '*.v' -Recurse |
        Where-Object { $_.FullName -notmatch 'ui_ram_|divider_gate' } |
        ForEach-Object { $_.FullName }
    $ispVvp = Join-Path $buildDir 'isp.vvp'
    $gammaVvp = Join-Path $buildDir 'gamma.vvp'
    & (Join-Path $IcarusBin 'iverilog.exe') -g2012 -s tb_dsi_gamma22 -o $gammaVvp `
        sim/tb_dsi_gamma22.sv @ispFiles
    if ($LASTEXITCODE -ne 0) { throw 'Gamma compilation failed' }
    & (Join-Path $IcarusBin 'vvp.exe') $gammaVvp `
        2>&1 | Tee-Object (Join-Path $buildDir 'gamma.log')
    if ($LASTEXITCODE -ne 0) { throw 'Gamma equivalence failed' }
    & (Join-Path $IcarusBin 'iverilog.exe') -g2012 -s tb_dsi_color_diagnosis -o $ispVvp `
        sim/tb_dsi_color_diagnosis.sv uisrc/01_rtl/system_top.v `
        (Join-Path $buildDir 'legacy_reference.v') `
        uisrc/03_ip/ui_csi_raw/ui_raw10_unpacket_4lane.v `
        uisrc/03_ip/ui_csi_raw/ui_image_correction.v @ispFiles `
        2>&1 | Tee-Object (Join-Path $buildDir 'isp_compile.log')
    if ($LASTEXITCODE -ne 0) { throw 'ISP compilation failed' }
    & (Join-Path $IcarusBin 'vvp.exe') $ispVvp `
        2>&1 | Tee-Object (Join-Path $buildDir 'isp_rgb.log')
    if ($LASTEXITCODE -ne 0) { throw 'ISP RGB test failed' }
    & (Join-Path $IcarusBin 'vvp.exe') $ispVvp +CSI `
        2>&1 | Tee-Object (Join-Path $buildDir 'csi_rgb.log')
    if ($LASTEXITCODE -ne 0) { throw 'CSI RGB test failed' }
    & (Join-Path $IcarusBin 'vvp.exe') $ispVvp +CSI +FS_WRAP `
        2>&1 | Tee-Object (Join-Path $buildDir 'fs_wrap_after.log')
    if ($LASTEXITCODE -ne 0) { throw 'Bayer phase rollover test failed' }
    if ($FullFrame) {
        & (Join-Path $IcarusBin 'vvp.exe') $ispVvp +CSI +FS_WRAP +FULL `
            2>&1 | Tee-Object (Join-Path $buildDir 'full_frame.log')
        if ($LASTEXITCODE -ne 0) { throw 'Full frame geometry test failed' }
    }
    $transportVvp = Join-Path $buildDir 'transport.vvp'
    & (Join-Path $IcarusBin 'iverilog.exe') -g2012 -s tb_dsi_color_transport -o $transportVvp `
        sim/tb_dsi_color_transport.sv uisrc/01_rtl/system_top.v `
        uisrc/03_ip/ui_dbuf/sfifo/sfifo.v `
        uisrc/03_ip/dsi/hdl_source/rgb_24b_to_32b.v `
        uisrc/03_ip/dsi/hdl_source/fifo_w32_d512/fifo_w32_d512.v `
        uisrc/03_ip/dsi/hdl_source/dsi_video_mode_packet.v `
        2>&1 | Tee-Object (Join-Path $buildDir 'transport_compile.log')
    if ($LASTEXITCODE -ne 0) { throw 'Transport compilation failed' }
    & (Join-Path $IcarusBin 'vvp.exe') $transportVvp `
        2>&1 | Tee-Object (Join-Path $buildDir 'transport_rgb.log')
    if ($LASTEXITCODE -ne 0) { throw 'Transport test failed' }
    $filterVvp = Join-Path $buildDir 'antialias.vvp'
    & (Join-Path $IcarusBin 'iverilog.exe') -g2012 -s tb_dsi_antialias -o $filterVvp `
        sim/tb_dsi_antialias.sv uisrc/03_ip/ui_isp/ui_isp_top.v
    if ($LASTEXITCODE -ne 0) { throw 'Filter compilation failed' }
    & (Join-Path $IcarusBin 'vvp.exe') $filterVvp +FULL `
        2>&1 | Tee-Object (Join-Path $buildDir 'antialias.log')
    if ($LASTEXITCODE -ne 0) { throw 'Antialias test failed' }
    Write-Output "DSI_COLOR_ALL_SIM_TESTS_PASS: $buildDir"
} finally {
    Pop-Location
}

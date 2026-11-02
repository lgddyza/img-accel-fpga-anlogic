# EHP2 + DSI DC16 color/aliasing correction (2026-10-16)

Open this folder's `fpga_prj_jpeg.al` in TD. Do not use the old project's bit.
This revision needs a new synthesis, route, timing check and bit generation.
No new bit has been generated/programmed by this change.

- DSI tracks the retained RAW sensor row parity and decodes Bayer accordingly.
- The DSI interpolation shares existing RAW line/window memories. The old
  PCIe ISP/crop stream is preserved and compared against the 14 Oct sources.
- A DSI-only 2x2 RGB antialias filter precedes 1920x1080 -> 1024x576 decimation.
- DSI Gamma uses an exactly equivalent logic lookup to save scarce ERAM.
- Pure RGB/white reference squares appear beside the FPS display.
- User BAR 0x108 reads `0x44433136` (DC16); DSI controls are at 0x10c/0x110.
- `tools/dsi_control.py` runs on RK and changes only the DSI branch.

Diagnosis, validation evidence and board checks: `DSI_FIX_20261016.md`.
Run `tools/run_dsi_color_diagnosis.ps1` for the reproducible numerical tests.
Final gate synthesis passed: Slice 49,207/64,320 (76.50%), ERAM 256/272
(94.12%), DSP 134/240 (55.83%). Placement/routing and final timing are pending.

## Preserved 14 Oct revision history

Derived from the preserved `../IMX415_DSI_PCIE_JPEG_EHP2_DSI_COLOR_20261014`
project; top `system_top`, device `PH1A90SEG324-2`, TD 2026.1 SP2.
The 14 Oct revision removed the forced gray conversion, and the user built
and downloaded its bit (SHA256 `d989bdff55e931fadc4c4e8499f4806885f692eea349a31b59ded64ae68f48c4`).
That original folder and its build outputs are preserved. This DC16 folder
does not include that old bit. The frozen legacy simulation reference is
under `sim/reference_20261014/` so regression tests are self-contained.

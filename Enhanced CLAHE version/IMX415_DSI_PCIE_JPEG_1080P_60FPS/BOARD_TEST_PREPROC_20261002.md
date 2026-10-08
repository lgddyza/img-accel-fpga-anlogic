# 2026-10-02 preprocessing board test

The user reported programming the first preprocessing candidate. FPGA BAR
reads match this project's 1920×1080 GREY ABI 5 register map, including the
new mode register at `0xA4`. The programmed bit was not read back for a hash
comparison. The RK3576 was reached through COM12 at 1,500,000 baud because
the previous direct SSH address was not reachable.

## RK recovery and display

An old HDMI viewer was still issuing DMA requests after FPGA programming;
the SGDMA engine ID read as `0xffffffff`. The viewer was stopped, the gray
V4L2 and `anlogic_pci` modules were unloaded, and RK `2a210000.pcie` was
unbound and rebound. The endpoint then enumerated at `21:00.0` as PCIe Gen2
x1; the same gray V4L2 module loaded at `/dev/video73`.

The FPGA BAR returned width 1920, height 1080, format `GREY`, ABI
`0x47520005`, initial mode 3, and Gaussian overrun 0. Five DMA frames in
mode 3 each had the correct 2,073,600-byte length but every pixel was zero.
Controlled mode comparisons on the same scene:

| Mode | Result from GREY8 capture |
| --- | --- |
| 0, grayscale only | Five complete nonzero frames; means 77.36, 82.10, 77.21, 82.20, 77.55 |
| 1, Gaussian only | Four complete nonzero frames; means 77.22, 82.28, 77.53, 82.36 |
| 2, histogram equalization only | Four complete frames, all zero |
| 3, Gaussian and histogram equalization | Five complete frames, all zero |

The board was left in **mode 1**. The mode tool was copied to
`/root/imx415_pcie_gray_1080p/preproc_mode.py`; its `status` command read
`mode: 1 (gauss)` and Gaussian padding overrun 0. The viewer is running from
`/root/imx415_pcie_gray_1080p/show_gray_hdmi.py /dev/video73 188` with log
`hdmi_preproc_gauss.log`. DRM reports `card0-HDMI-A-1/status` as connected.
The viewer reports 59.9–60.0 sink FPS; the user confirmed a normal grayscale
picture on the HDMI display. [This 640×360 preview](captures/preproc_mode1_preview.jpg)
was made from a GREY8 input frame, not a physical screen capture.

In one 20-second interval, BAR complete-frame count increased by 1,198,
pass count by 1,198, drop count by 1, error count by 2, and Gaussian overrun
remained 0. The driver rejected one 1,056,768-byte short frame, consistent
with an intermittent short-frame issue observed before preprocessing.

## Histogram issue and next verification

The histogram module originally read and cleared one ERAM bin in the same
clock. On this FPGA, read-during-write data is not guaranteed to be the old
count; an all-zero LUT explains the observed black frames. The source now
uses separate `READ_BIN` and `CLEAR_BIN` states. The small four-frame test,
complete 1080p four-level equalization test, preprocessing integration test,
and complete 1080p constant-frame test all pass in simulation. TD route and
bit generation also pass: setup WNS +0.573 ns, hold WNS +0.020 ns, slice
23,741/64,320, ERAM 117/272, and DSP 36/240. The fixed candidate is
`tools/preproc_histfix_candidate.bit`, SHA-256
`1B3D098174ABD828B4B0E521243B0E314FB1A0A70C772B38E0D9581B34B64507`.
This is still a hardware diagnosis rather than a verified fix until that bit
is programmed and modes 2 and 3 are retested. Keep mode 1 for visible HDMI
with the first candidate bit.

## Histogram fix board verification

The user programmed `preproc_histfix_candidate.bit`. The old RK DMA context
then returned an invalid engine ID, as expected after FPGA reconfiguration.
The HDMI viewer and both PCIe modules were stopped, RK `2a210000.pcie` was
unbound and rebound, and the endpoint enumerated again as PCIe Gen2 x1 at
`21:00.0`. The GREY driver registered `/dev/video73` and the BAR reported ABI
5, 1920x1080, initial mode 3, and Gaussian padding overrun 0.

Six complete 2,073,600-byte frames were captured in every mode. Modes 0 and 1
were nonzero across every pixel, with means alternating around 64 and 68 for
the current scene. Mode 2 produced the full 0..255 range, 99.27% to 99.63%
nonzero pixels, and means from 111.98 to 146.03. Mode 3 also produced the full
0..255 range, 99.52% to 99.69% nonzero pixels, and means from 111.71 to 146.46.
This verifies on hardware that the histogram read/clear fix removed the black
output in both histogram modes.

The board was left in **mode 3**, Gaussian plus histogram equalization. The
HDMI viewer is running as PID 45866 from `/dev/video73` on connector 188, with
log `/root/imx415_pcie_gray_1080p/hdmi_preproc_histfix_all.log`. DRM reports
`card0-HDMI-A-1` connected and both capture and sink remain at 60.0 FPS. In a
15-second interval the FPGA complete and pass counters each increased by 898,
Gaussian padding overrun stayed 0, and one known 1,056,768-byte short frame
was rejected without interrupting HDMI output.

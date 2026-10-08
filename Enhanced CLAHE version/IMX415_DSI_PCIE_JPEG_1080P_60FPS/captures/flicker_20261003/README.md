# HDMI flicker measurement, 2026-10-03

The user observed rapid HDMI brightness flicker while the board was showing
preprocessing mode 3. The RK HDMI viewer reported 60.0 sink FPS, the connector
was connected, and the FPGA reported mode 3 with Gaussian overrun 0.

The viewer was briefly stopped. On the same camera scene, `v4l2-ctl` captured
20 consecutive complete 1920x1080 GREY8 frames in mode 3 (Gaussian plus
histogram equalization) and 20 in mode 1 (Gaussian only). Each capture was
41,472,000 bytes, exactly 20 times 2,073,600 bytes. The mode was returned to
3 and the HDMI viewer was restarted at 60 FPS.

One pixel in every 64 was sampled consistently from each frame. Across frames
4..19, the mean absolute jump between adjacent whole-frame sampled means was
28.19 gray levels in mode 3 and 4.92 in mode 1, a 5.73x increase. The mean
absolute difference two frames apart was only 0.15 and 0.06 respectively.

Mode 3 means were approximately 139.5, 111.4, 139.5, 111.4, ... . Mode 1
means were approximately 73.4, 78.3, 73.4, 78.3, ... . The two-state source
brightness variation is already present with equalization disabled. The
framewise histogram LUT amplifies it. At 60 new frames per second, alternating
bright/dark frames produce roughly 30 Hz luminance flicker. The capture is
upstream of RK color conversion and HDMI output, so the screen link is not
the source of the measured alternation.

This experiment does not establish whether the original two-state variation
comes from scene lighting, a filmed monitor, sensor exposure, or an earlier
FPGA camera/ISP stage. To separate them, hold the camera and settings fixed,
remove other displays from the scene or use stable DC lighting, and repeat the
mode-1 capture. Disappearance of the 4.92-level alternation supports an
illumination origin; persistence points toward sensor/ISP timing. A practical
short-term display choice is mode 1 or fixed-phase 30 FPS selection. A future
60 FPS mode-3 implementation should smooth the histogram LUT across frames
and make equalization strength adjustable.

Temporary raw captures on RK: `/run/flicker_mode3.gray` and
`/run/flicker_mode1.gray` (lost on reboot).

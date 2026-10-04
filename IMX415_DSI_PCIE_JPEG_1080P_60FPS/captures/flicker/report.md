# 2026-10-01: adjacent-frame flicker check

Captured 60 consecutive 1920x1080 GREY8 frames on RK from `/dev/video73`
while the HDMI viewer branch remained connected through GStreamer `tee`.
The raw capture was 124,416,000 bytes (`/dev/shm/flicker_60.gray` on RK).
After capture, the normal HDMI viewer was restarted. The compact numeric
result is in `../flicker_analysis.json`.

- A repeated two-state brightness alternation is present. Most adjacent
  frames have about 4 GREY levels of sampled mean absolute pixel difference;
  frames two positions apart have about 1.5 levels.
- Whole-frame means cluster at 26.1..26.3 and 28.2..28.4. The largest
  adjacent mean jump was 2.19 GREY levels, between frames 14 and 15.
- An upper-left tile containing a monitor changed by up to 21.3 levels.
  In the 640x360 preview, the monitor region changed by 9.4 levels MAD,
  the floor by 2.1, and the far dark area by 1.7. Frame-to-frame spatial
  correlation was 0.987 in the monitor and 0.975 on the floor.
- The reference sensor table selects WDMODE=0 and writes identical gain
  0x30 to all four gain registers. The top ties both manual gain keys high
  (inactive). An intentional FPGA gain alternation is therefore not visible
  in this source configuration.
- Frame 9 to 10 repeated the low state instead of alternating; the parity
  flipped afterward. A missed camera frame during capture is one possible
  explanation for that phase change, but it is not proved from images alone.
- The differences track the filmed monitor and its reflected illumination.
  The inspected pairs have no broad horizontal/vertical rectangular transport
  blocks analogous to the earlier purple/green RGB failure. Gray transport
  removes the purple/green color appearance, but it has not removed this
  luminance fluctuation.

`frame_0.png`/`frame_1.png`, `frame_10.png`/`frame_11.png` and
`frame_14.png`/`frame_15.png` are adjacent downsampled images.
`diff_0_1.png`, etc. are contrast-stretched absolute differences used only
to visualize where the change occurs.

To separate scene/lighting flicker from the FPGA/PCIe path, repeat this
60-frame capture with the filmed monitor covered or switched to a steady
black/white field, changing only that one variable. If the two-state
component disappears, it came from the screen/light. If it persists, compare
the DSI panel at the same time: shared flicker points to camera/ISP or light;
HDMI-only flicker points to the PCIe/RK display path.

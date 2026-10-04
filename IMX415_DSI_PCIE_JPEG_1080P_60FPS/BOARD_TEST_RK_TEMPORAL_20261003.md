# RK 60 FPS temporal stabilization, 2026-10-03

## Symptom and isolation

The user observed rapid brightness flicker on the HDMI monitor and reported
that the DSI camera picture was stable. The RK viewer remained at about 60
FPS, the HDMI connector was connected, and the FPGA reported preprocessing
mode 3 with Gaussian overrun 0.

On the same scene, RK V4L2 captured 20 consecutive full 1920x1080 GREY8
frames in each of two FPGA modes:

| Mode | Adjacent sampled mean jump | Two-frame-lag jump | Sampled 10/50/90 percentiles of alternating frames |
| --- | ---: | ---: | --- |
| 1: Gaussian, no equalization | 4.92 | 0.06 | roughly 34/76/107 and 37/81/114 |
| 3: Gaussian plus equalization | 28.19 | 0.15 | roughly 22/145/248 and 17/109/213 |

Each 20-frame capture was exactly 41,472,000 bytes. One pixel in every 64
was used consistently for the summary metrics. The source of the smaller
mode-1 alternation is not yet isolated, but the framewise equalizer amplifies
it by about 5.7 times in mode 3.

## RK filter

`deploy/rk_temporal_gray.c` registers the in-place `rktemporalgray`
GStreamer element for GREY8. It samples the 10th, 50th and 90th percentiles
of each frame and matches them to a slowly moving reference through a
monotonic 256-entry lookup table. A limited mean correction removes the
remaining global brightness pulse. The filter is between `capssetter` and
`videoconvert`, so the HDMI RGBx conversion and small FPS overlay remain.
It does not drop frames or change the FPGA mode. `HDMI_TEMPORAL=0` disables
the new element for comparison.

An offline RK GStreamer replay of the 20 mode-3 frames produced all
41,472,000 expected output bytes. The adjacent sampled mean jump fell from
28.19 to 0.76 levels, a 97.3% reduction. Six inspected output frames had
10/50/90 percentiles around 20-25 / 141-146 / 244-249, retaining the broad
equalized contrast.

The live viewer ran with the filter enabled. A short HDMI sink input capture
contained eight complete 8,294,400-byte 1920x1080 RGBx frames; their sampled
adjacent mean jump was 1.18 levels. This capture writes each 8 MB buffer to
RAM and is not a frame-rate benchmark. In a separate 111-second ordinary
display observation after startup, the sink mean was 59.69 FPS, 105 seconds
were at least 59 FPS, and three seconds were below 58 FPS. The earlier
intermittent short DMA frame remains a possible cause of occasional low
seconds; this test does not establish the cause of each drop.

The user confirmed that visible HDMI flicker had markedly decreased. The
board was left on FPGA mode 3 with one RK viewer using `rktemporalgray`.
The DSI path was not modified. Live log: `/run/hdmi_temporal_20261003.log`
on the RK (RAM, lost on reboot). The deployed plugin and viewer are under
`/root/imx415_pcie_gray_1080p/`.

The RK root partition was full before deployment. `/var/log/kern.log` had
grown to 2.5 GB during prior PCIe DMA error spam; its last 1 MB was saved to
`/run/kern.log.tail.before_cleanup` and the generated log was truncated.
This freed approximately 1.8 GB for the persistent plugin build.

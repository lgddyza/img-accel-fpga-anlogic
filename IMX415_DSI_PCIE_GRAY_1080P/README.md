# IMX415 dual display: grayscale DSI + 1080p GREY PCIe/HDMI

Open `fpga_prj.al` in Anlogic TD. Top module: `system_top`; target:
PH1A90SEG324-2. This is an independent copy of the previously routed
`IMX415_DSI_PCIE_GRAY` project. Do not use the older
`IMX415_PCIE_GRAY_1080P` bitstream for the dual-display test: it has no DSI
output. The user synthesized and programmed this new two-output source on
2026-10-01.

## Simultaneous paths

```text
IMX415 RAW10 -> correction/ISP RGB888 (1920x1080, four pixels/clock)
                  +-> BT.601 luma -> RGB gray 8:15 downscale -> DDR 1024x576 -> 1024x600 DSI
                  |                                      (12 black rows top/bottom)
                  +-> BT.601 luma -> async FIFO -> SGDMA C2H
                                                                -> RK3576 HDMI
```

The DSI panel receives the entire grayscale camera frame scaled from 1920x1080 to
1024x576, preserving 16:9. The panel still runs at 1024x600; the top and
bottom 12 rows are black. The previous version only read the upper-left
1024x600 crop from DDR. The copied demo ISP's final saturation stage could
output grayscale. The active ISP output now bypasses that stage and uses its
RGB brightness-stage output directly. The PCIe tap computes BT.601 gray
independently from the full 1920x1080 RGB stream. A small logic-only
status layer in `system_top.v` draws `DSI 1024x600`
and `FPS:nn` at the upper left. Its FPS counts panel vsync pulses during each
50 MHz clock second; this is the DSI scanout rate, not the number of distinct
camera frames. With the 1312x635 timing it should read about 60 FPS. The
PCIe path taps the ISP output before the DSI scale and
produces a full 1920x1080 `GREY` image. Its FIFO and frame drop logic never
backpressure the ISP or DSI.

One frame is exactly 2,073,600 bytes (129,600 128-bit DMA beats). The FPGA
validates 480 four-pixel beats per row and 1080 rows per frame. A malformed
line, early new frame or FIFO overflow terminates an in-progress DMA packet
with a short abort packet. The RK driver rejects short frames by default.

## RK ABI and files

The copied `deploy/v4l2_drv` driver matches the endpoint's ABI 5. It must be
loaded without `diagnostic_short_1066=1`; that option is only for an older
PCIe-only bitstream. `deploy/show_gray_hdmi.sh /dev/video73 188` starts the
GREY8 HDMI pipeline after the driver has created `/dev/video73`. The script
can find the gray video device automatically if called without a device. The
wrapper runs `deploy/show_gray_hdmi.py` (RK Python GI/GStreamer) and draws
`HDMI 1920x1080 FPS:nn.n` in one small text layer at the upper left. The FPS
comes from `fpsdisplaysink`'s measured sink rate and can be below the 60 Hz
HDMI link timing. The viewer clears the gray driver's erroneous V4L2
colorimetry metadata and converts full-range GREY8 to RGBx; without this
correction, GStreamer emitted `(Y,128,128)` instead of `(Y,Y,Y)` and the
HDMI picture appeared foggy. Neutral brightness/contrast is the default; optional
`HDMI_BRIGHTNESS` and `HDMI_CONTRAST` environment variables enable the
GStreamer `videobalance` element.

| BAR offset | Expected value |
| --- | --- |
| 0x44 / 0x48 | 1920 / 1080 |
| 0x4c | `0x59455247` (`GREY`) |
| 0x58 / 0x64 | 2,073,600 bytes |
| 0x5c | `0x47520005` (ABI 5) |
| 0x78 | 129,600 beats |
| 0x8c | DSI panel 1024x600 |
| 0x90 | camera mode 0 |
| 0x94 | ISP tap/framing/FIFO errors |

The BAR frame counter at 0x50 counts correctly framed camera images, 0x68
counts rejected PCIe frames, and 0x70 counts delivered DMA packet endings.

## Simulation and repeatable board checks

`sim/tb_isp_gray_1080p_cdc.v` sends a full 1920x1080 RGB test image with
periodic DMA stalls. Icarus Verilog confirms every grayscale byte and the
single frame end: 2,073,600 bytes in 129,600 beats. The separate
`sim/tb_short_frame_abort.v` reproduces the earlier 1066-row failure and
confirms that it becomes a short rejected DMA packet. `tools/check_sources.py`
confirms that all 85 project sources exist, local RTL parses, named ports
match, the ISP color setting is active, and the remaining demo source tree is unchanged.
`tools/tb_dsi_status_overlay.v` checks the DSI text pixels, passthrough,
line coordinates, 12-row letterbox and one-second frame counter.
`sim/tb_dsi_color_downscale.v` checks every output pixel of a complete
1920x1080 synthetic RGB frame against an independent 8:15 nearest-neighbour
coordinate formula, including 576 line endings and exactly one frame start.

After a new bitstream is programmed, repeat these checks:

1. DSI shows the complete grayscale camera frame at 1024x576 inside its
   1024x600 active area, with 12 black rows above and below.
2. RK enumerates the PCIe endpoint and the BAR reports ABI 5 and 1920x1080.
3. Reload the gray V4L2 driver with the diagnostic option disabled. Every
   accepted DMA packet must be exactly 2,073,600 bytes.
4. Start the HDMI viewer and check that its 1080p picture is grayscale while
   the DSI grayscale picture remains active.
5. If frames drop, compare 0x50, 0x68, 0x70 and 0x94 over several seconds.
   A rising 0x94 indicates ISP line timing or FIFO trouble; rising 0x68 with
   stable 0x94 points to PCIe descriptor availability or transport stalls.

## Hardware test on 2026-10-01

The user later reported the DSI panel displayed a gray camera image. The copied
demo's ISP grayscale setting caused this; the above color fix has not yet been
synthesized or programmed. After the earlier FPGA
programming, the old RK DMA session had stale PCIe mappings and timed out.
Stopping its HDMI process, unloading the gray and PCIe modules and rebinding
RK `2a210000.pcie` restored the endpoint. BAR0 then reported ABI 5,
1920x1080 GREY, 2,073,600 bytes and 129,600 beats, with zero initial ISP
tap errors. The gray V4L2 module was reloaded with
`diagnostic_short_1066=0`.

Three consecutive strict-mode V4L2 frames were captured to
`captures/full/frame_0.png` through `frame_2.png`. Every DMA length was
2,073,600 bytes. HDMI-A-1 is connected and enabled; DRM shows active
1920x1080@60 output on video_port0. The initial GStreamer viewer used a
four-buffer leaky queue, four-thread GRAY8-to-NV12 conversion and
`videobalance brightness=0.1 contrast=2.0`. The user subsequently programmed
the bitstream with DSI status text; see the newer test below.

In a representative 5-second live interval the FPGA's correctly framed
camera counter advanced 299 and DMA packet endings advanced 300; one frame
was rejected and the ISP/FIFO error counter rose by two. Thus live delivery
is close to 60 full frames/s, but occasional short packets still occur and
are rejected by the strict driver. The HDMI link timing is 60 Hz; the new
on-screen FPS value measures frames delivered to the HDMI sink and can be
lower than the link refresh rate.

The scene is very dark: raw GREY values in these captures span 8..40 with
mean about 9. `captures/full/frame_*_enhanced.png` applies offline contrast
stretch solely to reveal scene content; those images are not the literal
HDMI output. `captures/hdmi/frame_0.png` is a frame processed with the same
GStreamer brightness/contrast settings used for live HDMI. The reference
camera configuration sets gain register 0x3090 to 0x30 and its manual gain
keys are tied inactive. Better illumination or a future gain-control RTL
change would provide more image detail than RK-side brightness adjustment.

## Test after the DSI status bitstream

The old RK PCIe mapping again timed out after FPGA programming. The viewer was
stopped, `milianke_gray_v4l2` and `anlogic_pci` were unloaded, RK platform
device `2a210000.pcie` was unbound and rebound, then both modules were loaded.
Three consecutive strict-mode `GREY` frames were captured successfully, each
exactly 2,073,600 bytes. The original frames and the three buffers handed to
RK's `kmssink` after text rendering are saved in
`captures/after_bit_20261001/`. The latter show both resolution and measured
FPS in the upper left. They are sink input buffers, not optical photographs or
DRM writeback of the physical HDMI connector.

The brighter scene made the earlier brightness/contrast settings overexpose
the picture. The current viewer defaults to neutral levels. A brief controlled
benchmark on this RK measured about 30 FPS for conversion only, 20 FPS with
the old NV12 compact text path, and about 10 FPS with two large text layers.
The HDMI connector remains active at 1920x1080@60. On the current bitstream,
the corrected RGBx live viewer presents about 20-30 new frames/s with status
text, depending on processing load. Faster processing or hardware overlay would still be required for 60
new displayed frames/s.

## Color/gray correction attempted on 2026-10-01

The 2026-10-01 ISP color change was in source only until the user built and
programmed a new bitstream. The 2026-10-02 correction below supersedes this
attempt. In a 100,005-color numerical sample, grayscale derived from the
restored near-neutral RGB differs from the old ISP gray by only -2..0 levels.
The RK HDMI viewer change is already deployed and running. A controlled replay
of one strict 1920x1080 GREY8 frame showed that the driver's `colorimetry=2:0:0:0`
metadata caused live GStreamer conversion to write `(Y,128,128)` into RGBx.
After `capssetter replace=true` removed that metadata, a live captured HDMI
sink input buffer had equal R, G and B on every sampled pixel outside the
status text; it remained 1920x1080 and measured about 29.5 FPS. This is a
buffer-level verification, not an optical photograph of the HDMI monitor.

## HDMI brightness alternation, 2026-10-01

The user observed alternating HDMI brightness and reported that the DSI panel
did not visibly flicker. A strict V4L2 capture of 120 consecutive full GREY8
frames showed an exact bright/dark alternation at the raw PCIe image level:
even-frame sampled mean 78.25, odd-frame mean 74.79, and lag-one correlation
-0.991. Frames 0 and 2 were much closer to each other than frames 0 and 1.
The FPGA BAR advanced 180 full frames in 3 seconds while rejected-frame and
ISP/FIFO error counters stayed constant. This proves the HDMI color conversion
is not creating the alternation; it does not by itself locate the cause before
the RK V4L2 boundary.

The older course project's `mipi_csi_2/mipi_csi_rx.v` is not instantiated or
listed in this TD project. The five files in this project's active
`al_ip/mipi_rx` folder are byte-identical to the supplied `415_mipi` reference.
Replacing `mipi_csi_rx.v` would therefore not change this build.

The current HDMI script uses `videorate drop-only=true` to select 30 frames/s
at a fixed phase before RGBx conversion and text rendering. This changes
only RK display processing; the FPGA still sends about 60 full GREY8 frames/s
and DSI remains on its independent path. The viewer previously rendered about
20-30 new frames/s, so fixed-phase selection makes its frame choice stable.
In a separate 61-frame selected capture, discarding the first startup frame
left 60 frames with sampled brightness mean 74.815 and standard deviation
0.056, versus 1.73 before selection. Six live HDMI sink input captures had
mean values 77.55-77.65 after excluding the text rows; all sampled pixels had
equal RGB components. `tools/analyze_flicker.py` reproduces the GREY8 frame
statistics on the RK board.

The upstream reason for two alternating exposure levels is still unproven.
A minimal follow-up test is to keep all software unchanged, point the camera
at steady DC illumination with the other computer monitor out of view, and
recapture 120 raw frames. If alternation remains, inspect sensor frame-gain
configuration and the ISP/camera frame boundary. If it disappears, the light
source or monitor is the cause. The current fixed-phase HDMI path suppresses
the visible brightness alternation in either case.

## DSI full-frame RGB correction, 2026-10-02

The user reported that the programmed DSI image was still grayscale and that
only the upper-left camera window was visible. The old DDR read settings
(`R_XSIZE=1024`, `R_XSTRIDE=1920`, `R_YSIZE=600`) explain the crop exactly.
The revised DSI-only write branch selects 8 of each 15 RGB pixels and rows,
yielding 1024x576 RGB frames. DDR now stores packed 1024x576 frames and reads
576 complete lines while the DSI scanout inserts 12 black rows at both edges.
The ISP explicitly bypasses the final saturation/grayscale module; its RGB
brightness-stage stream feeds both the DSI scaler and the separate PCIe
grayscale converter. HDMI still receives a full 1920x1080 GREY8 stream.

`sim/tb_dsi_color_downscale.v` passed a complete-frame pixel, line and frame
check; `tools/tb_dsi_status_overlay.v` passed the letterbox, overlay and timing
check; `sim/tb_isp_rgb_tail.v` confirmed distinct RGB channels pass the final
brightness and 96-to-128-bit packing stages; `tools/check_sources.py` passed
manifest, syntax and connection checks.
This source was subsequently synthesized and routed on 2026-10-02, with the
latest bitstream generated at 00:49 local time. The user programmed a bitstream
and reported the DSI behavior below; the exact programmed file is not
independently identifiable from the existing BAR register set.

## DSI report after the 2026-10-02 bitstream

The user reports a stable grayscale HDMI image, but the DSI camera image is
still gray and flashes. The active RTL already bypasses the old grayscale
saturation stage, and the full-frame DSI scaler passes a synthetic RGB frame
in simulation. Those checks do not establish whether live ISP output or the
physical DSI link carries color. The status panel background is hard-coded
dark blue (`24'h102840`); observing whether that panel is blue will separate
an upstream camera/ISP problem from a downstream DSI/output problem.

The DSI scanout previously ran at 50 MHz / (1344 * 635) = 58.59 FPS against
the roughly 60 FPS camera. The new RTL sets HTOTAL=1312 and HFP=128 while
keeping 1024x600 active pixels and the vertical timing, giving 60.015 FPS.
This removes the rapid frame-buffer phase drift as one plausible source of
flashing. It is an RTL change only; the board has not yet run this version.

## DSI color branch and on-board diagnosis, 2026-10-02

The user flashed the scanout-timing version and observed a blue status panel,
stable DSI scanning, and a still-gray camera image. The blue panel proves the
physical DSI output can carry RGB but does not prove the live ISP and DDR image
contain RGB chroma. The reference color-camera project at
`E:/FPGA/03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1`
uses gray-world AWB followed by saturation adjustment. The new DSI-only write
branch follows that sequence before the 8:15 full-frame scaler. Its AWB gain
is calculated from four frames of samples and applied only at a frame boundary;
the original per-pixel divider output could otherwise cause gain changes within
a frame. The PCIe/HDMI gray tap continues to use the original ISP output.

BAR user register `0xA4` is a read-only sticky chroma observation, with bit 0
for ISP RGB, bit 1 for DSI DDR write, and bit 2 for DSI DDR read. A flag sets
after 1024 sampled pixels have an R/G or B/G difference above 16. Point the
camera at a saturated colored object, allow a second for flags to accumulate,
then run `python3 deploy/read_dsi_color_diag.py` on the RK. `0x0` means color
was already absent at the ISP output or the scene did not contain enough color;
`0x1` means the DSI processing/scaler lost it; `0x3` means the DDR/read path
lost it; `0x7` with a visibly gray image moves the investigation to the video
readout/format. These flags are available only after synthesizing and flashing
this revision, not in the bitstream currently on the board.

The DSI AWB module is embedded in the already-registered `system_top.v`; the
Tang Dynasty GUI overwrote an earlier project manifest entry for a standalone
AWB file, causing `dsi_frame_awb is a black box` at elaboration. The embedded
module was checked with a behavioral-divider simulation covering
frame-held gains, RGB correction, and SOF/EOL alignment. The static project
source/connection checker also passes. Full synthesis and board color results
still need the user's next build and flash.

## DSI grayscale stability rollback

After flashing the AWB/saturation revision, the user observed alternating
purple and green on DSI. The earlier full-frame version had a stable gray DSI
image. The AWB and saturation branch, its divider logic and chroma diagnostics
have therefore been removed from the active RTL. The original 8:15 full-frame
scaler, 1024x576 picture with 12-pixel black bars, and 60.015 Hz scanout timing
remain. Before scaling, each of the four ISP pixels is now explicitly mapped
to `{0,Y,Y,Y}` with BT.601 luma weights. This keeps all DSI color channels
equal even if the upstream ISP contains chroma. The PCIe/HDMI tap remains at
the same ISP point and still produces 1920x1080 GREY8 independently. This
rollback was subsequently synthesized, flashed, and reported stable on DSI.

## RK HDMI 60 FPS display path

After the grayscale rollback bitstream was flashed, the FPGA/RK capture path
delivered 60.00 full 1920x1080 GREY frames/s to a test sink. The older RK
viewer was limited to 30 FPS by an explicit `videorate` stage. Removing that
stage alone still gave about 29.5 FPS on the HDMI sink because the Rockchip
KMS sink was waiting for vertical sync twice. `skip-vsync=true` raised the
rendered rate to about 59 FPS while retaining the 60 Hz HDMI mode.

The standard GStreamer `textoverlay` then accounted for roughly one lost frame
per second when its FPS text changed. `deploy/rk_fast_osd.c` is a small in-place
RGBx GStreamer filter that draws only a 344x32-pixel panel and counts input
frames. Build it on the RK with `sh deploy/build_rk_fast_osd.sh`; the HDMI
wrapper also builds it automatically when the local `.so` is missing and a C
compiler is available. `deploy/show_gray_hdmi.py` uses the filter when present
and retains the standard text overlay as a fallback.

The live HDMI viewer reported 60.0 FPS for both the OSD input and the HDMI
sink over most of a sustained observation, with one isolated 58 FPS second
before returning to 60.0. A separate five-second test including startup
rendered 299 frames (59.8 FPS). The HDMI connector remained active at
1920x1080@60. An occasional short camera DMA frame is still rejected by the
strict driver; RK display optimization cannot create a missing camera frame.
The observed short packet was 1,056,768 instead of 2,073,600 bytes about
every 17.07 seconds. Over one 18-second interval BAR capture frames advanced
1080, while the FPGA tap error count increased by 2 and drop count by 1,
placing this residual fault upstream of RK color conversion and KMS display.

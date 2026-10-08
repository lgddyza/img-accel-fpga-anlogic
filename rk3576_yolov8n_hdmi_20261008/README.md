# RK3576 YOLOv8n HDMI deployment snapshot (2026-10-08)

This package captures the **running RK-side software deployment**, not a disk image. `board.tar.gz` was made on the RK3576 and transferred over COM12 with per-packet CRC32 and whole-file SHA256 verification. Its paths are relative to `/`; preserve them when restoring.

## Contents

- `board.tar.gz`: the deployed 640x640 INT8 six-class RKNN model; HDMI/YOLO launch scripts; viewer, overlay and status-plane sources and binaries; GStreamer plugins; PCIe and three JPEG kernel modules; recovery script, modprobe configuration and systemd units. The tar lists 34 files.
- `source/rk3576_infer.cpp` and `source/rknn_api.h`: PC-side copies of the source and header used to build the inference library. The exact deployed `libroad_infer.so` is in the tar.
- `source/test_temporal_overlay.py` and `source/test_status_ai.py`: local pixel-level overlay and status-plane checks.
- `SHA256SUMS`: checksums of the files next to it. Verify before use with `sha256sum -c SHA256SUMS` (Linux) or `Get-FileHash` (PowerShell).

Training data, weights other than the deployed RKNN, previous rollback plugins, logs, FPGA bitstream, root filesystem and OS shared libraries are outside this RK software snapshot. In particular, do not add `/root/jpeg_rk/rollback_ai_osd` to `GST_PLUGIN_PATH`: an old plugin with the same GStreamer element name previously caused the wrong overlay to load.

## Captured running configuration

- Board: RK3576 with 2 GB RAM; Linux `6.1.99`, aarch64. The bundled `.ko` files are tied to this kernel build. Python 3.11.2, GStreamer 1.22.9, OpenCV 4.6.0, libdrm 2.4.114, and `/lib/librknnrt.so` were present on the tested root filesystem.
- Input: FPGA PCIe transfer through `anlogic_pci` and three `milianke_jpeg` channels. The FPGA must deliver its existing JPEG stream; this package does not configure the FPGA.
- HDMI: connector `188`, 1920x1080p60 KMS, software JPEG decode, 3 decode workers, affine temporal processing and RGBx output. Current process uses `start_jpeg_hdmi_ai_fallback.sh 188`, which switches to the original viewer if AI exits.
- Detection: `road_damage_yolov8n_gray640_int8_rk3576.rknn`, SHA256 `ecdc6accd6558c3394d4a73eeb03b876f09d9e82ba11c2754869d8bb9add55ae`; interval 2 reconstructed frames; confidence 0.10; six labels from the original dataset. White 4-pixel boxes and confidence text are painted on the video. The independent transparent status plane refreshes once per second.
- Displayed `FPS:60` is static nominal input rate. The `YOLO FPS` readout is dynamic. Neither readout proves HDMI actually presented 60 distinct frames each second.

On the running board, `anlogic_pci` and all three JPEG modules were loaded; `pcie1-recover.service` was active. `anlogic-sgdma.service` was enabled but inactive, so do not treat its active state as proof of module availability; check `lsmod` and the JPEG devices. The AI viewer is started from the serial root shell, not a dedicated enabled service.

## Measured behavior and limits

In the roughly 140-second run recorded in the project README, distinct JPEG frames were reconstructed at about 59.96 FPS, YOLO completed at about 29.96 FPS, and HDMI presented at about 57.8 FPS. A longer nearby run recorded reconstruction at 59.98 FPS, but scene and quality factor changed between windows. The original HDMI viewer also measured roughly 57.3-57.5 FPS in adjacent tests. This snapshot preserves the best tested `interval=2` compromise; it does **not** certify lossless 60 FPS HDMI or fine-crack recall on the user's actual aerial video.

## Verify and restore on a compatible board

First verify the archive and inspect its paths:

```sh
sha256sum -c SHA256SUMS
tar -tzf board.tar.gz
```

For restoration, use a matching RK3576 image and `6.1.99` kernel. Back up the current `/root/jpeg_rk`, `/root/road_damage_yolov8n`, the listed `/etc` files and `/lib/modules/6.1.99/extra/anlogic_pci.ko` before extraction. Stop the current fallback shell and its viewer/status descendants, then, as root from the package directory:

```sh
test "$(uname -r)" = 6.1.99
tar -xzf board.tar.gz -C /
depmod -a 6.1.99
systemctl daemon-reload
systemctl enable pcie1-recover.service anlogic-sgdma.service
```

The source and compiled plugins are both present. Keep their original modification times from the tar; the launch script rebuilds stale plugins if a compiler is installed. On a fresh boot, check `lsmod` for `anlogic_pci` and all three `milianke_jpeg_*` modules, plus the expected JPEG devices. The three JPEG modules are board-specific and may need to be loaded through the existing board startup procedure if the root filesystem does not already do so. The package does not claim to reproduce that uncollected boot wiring.

With the FPGA stream and HDMI connector available, start from a root shell:

```sh
nohup sh /root/jpeg_rk/start_jpeg_hdmi_ai_fallback.sh 188 \
  > /root/road_damage_yolov8n/hdmi_ai_fallback_console.log 2>&1 < /dev/null &
```

Check the active model and plugins, not only that processes exist:

```sh
sha256sum /root/road_damage_yolov8n/road_damage_yolov8n_gray640_int8_rk3576.rknn
lsmod | grep -E 'anlogic_pci|milianke_jpeg'
gst-inspect-1.0 rktemporalai | grep Filename
tail -n 20 /root/road_damage_yolov8n/hdmi_ai_ui_fixed.log
tail -n 20 /root/road_damage_yolov8n/hdmi_status_plane.log
```

The `gst-inspect` filename should resolve to `/root/jpeg_rk/active_ai_plugins/libgstrktemporalai.so`; the wrapper sets its own GStreamer registry. If the AI viewer exits, the fallback script runs `/root/jpeg_rk/start_jpeg_hdmi_60.sh` to maintain the original HDMI video path. Do not launch another viewer while one is using the JPEG devices and DRM output.

## Provenance

Host capture date: 2026-10-08 (Asia/Shanghai). The board's clock was not synchronized, so its file timestamps are not reliable capture dates. The archive SHA256 is recorded in `SHA256SUMS`; it matched the value printed on the board before serial transfer. The project [README](../../README.md) contains the tuning history and accuracy caveats.

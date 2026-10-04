#!/usr/bin/env python3
"""RK HDMI viewer: one text layer for resolution and measured sink FPS."""

import argparse
import os
from pathlib import Path
import signal

import gi

gi.require_version("Gst", "1.0")
from gi.repository import GLib, Gst  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("video_device")
    parser.add_argument("connector", type=int)
    parser.add_argument("--capture-count", type=int, default=0)
    parser.add_argument("--compare-count", type=int, default=0,
                        help="capture matched GREY8 frames before and after RK temporal filter")
    parser.add_argument("--capture-dir", type=Path, default=Path("/dev/shm"))
    args = parser.parse_args()
    if not args.video_device.startswith("/dev/video") or args.connector < 0:
        parser.error("Expected a /dev/video device and a numeric connector ID")
    if args.capture_count and args.compare_count:
        parser.error("Choose either --capture-count or --compare-count")

    brightness = float(os.environ.get("HDMI_BRIGHTNESS", "0"))
    contrast = float(os.environ.get("HDMI_CONTRAST", "1"))
    if not -1.0 <= brightness <= 1.0 or not 0.0 <= contrast <= 2.0:
        parser.error("HDMI_BRIGHTNESS must be -1..1 and HDMI_CONTRAST 0..2")

    plugin_dir = Path(__file__).resolve().parent
    fast_osd = (plugin_dir / "libgstrkfastosd.so").is_file()
    temporal_gray = (
        os.environ.get("HDMI_TEMPORAL", "1") != "0"
        and (plugin_dir / "libgstrktemporalgray.so").is_file()
    )
    if args.compare_count and not temporal_gray:
        parser.error("--compare-count requires the RK temporal GREY plugin")
    if fast_osd or temporal_gray:
        previous = os.environ.get("GST_PLUGIN_PATH", "")
        os.environ["GST_PLUGIN_PATH"] = str(plugin_dir) + (
            os.pathsep + previous if previous else ""
        )
    Gst.init(None)
    balance = ""
    if brightness != 0.0 or contrast != 1.0:
        balance = f"! videobalance brightness={brightness} contrast={contrast} "
    status_layer = (
        "! rkfastosd " if fast_osd else
        '! textoverlay name=status text="HDMI 1920x1080 FPS:--" '
        'halignment=left valignment=top deltax=24 deltay=24 '
        'shaded-background=false font-desc="Sans Bold 18" '
    )
    description = (
        f"v4l2src device={args.video_device} io-mode=mmap "
        "! video/x-raw,width=1920,height=1080,format=GRAY8,framerate=60/1 "
        # Preserve every camera frame. The RK capture, conversion and text
        # stages have each been measured at about 60 fps on this board.
        "! queue max-size-buffers=4 max-size-bytes=0 max-size-time=0 leaky=downstream "
        # The gray V4L2 driver advertises colorimetry=2:0:0:0. With that
        # metadata, videoconvert wrongly produces (Y,128,128) in RGBx. Remove
        # the metadata before conversion so each full-range GREY8 sample is
        # copied into R, G and B, matching the DSI grayscale appearance.
        '! capssetter name=raw_input caps="video/x-raw,format=(string)GRAY8,'
        'width=(int)1920,height=(int)1080,framerate=(fraction)60/1" replace=true '
        + ("! rktemporalgray name=temporal " if temporal_gray else "")
        + "! videoconvert n-threads=4 ! video/x-raw,format=RGBx "
        + balance
        + status_layer
        + "! fpsdisplaysink name=fps fps-update-interval=1000 "
        "text-overlay=false signal-fps-measurements=true silent=true sync=false "
        f'video-sink="kmssink name=screen connector-id={args.connector} '
        'sync=false skip-vsync=true"'
    )
    print(f"RK temporal GREY stabilizer: {'enabled' if temporal_gray else 'disabled'}",
          flush=True)
    pipeline = Gst.parse_launch(description)
    overlay = pipeline.get_by_name("status") if not fast_osd else None
    fps_sink = pipeline.get_by_name("fps")
    loop = GLib.MainLoop()
    errors = []

    def measured(_element, current, _dropped, _average):
        if overlay is not None:
            text = f"HDMI 1920x1080 FPS:{current:.1f}"
            GLib.idle_add(overlay.set_property, "text", text)
            print(text, flush=True)
        else:
            print(f"HDMI sink FPS:{current:.1f}", flush=True)

    def bus_message(_bus, message):
        if message.type == Gst.MessageType.ERROR:
            error, details = message.parse_error()
            errors.append(f"{error}: {details}")
            loop.quit()
        elif message.type == Gst.MessageType.EOS:
            loop.quit()

    fps_sink.connect("fps-measurements", measured)
    bus = pipeline.get_bus()
    bus.add_signal_watch()
    bus.connect("message", bus_message)
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())
    signal.signal(signal.SIGINT, lambda *_: loop.quit())

    if args.capture_count:
        args.capture_dir.mkdir(parents=True, exist_ok=True)
        captured = [0]
        armed = [False]

        def capture_sample(pad, info):
            if not armed[0]:
                return Gst.PadProbeReturn.OK
            buffer = info.get_buffer()
            if buffer is None:
                return Gst.PadProbeReturn.OK
            ok, mapping = buffer.map(Gst.MapFlags.READ)
            if not ok:
                errors.append("Cannot map HDMI sink buffer")
                GLib.idle_add(loop.quit)
                return Gst.PadProbeReturn.REMOVE
            try:
                data = bytes(mapping.data)
            finally:
                buffer.unmap(mapping)
            index = captured[0]
            path = args.capture_dir / f"hdmi_sink_{index}.raw"
            path.write_bytes(data)
            print(index, pad.get_current_caps().to_string(), len(data), buffer.pts,
                  flush=True)
            captured[0] += 1
            if captured[0] >= args.capture_count:
                GLib.idle_add(loop.quit)
                return Gst.PadProbeReturn.REMOVE
            return Gst.PadProbeReturn.OK

        fps_sink.get_static_pad("sink").add_probe(Gst.PadProbeType.BUFFER,
                                                   capture_sample)
        GLib.timeout_add(2200, lambda: (armed.__setitem__(0, True), False)[1])
        GLib.timeout_add_seconds(15, lambda: (loop.quit(), False)[1])

    compare_frames = []
    if args.compare_count:
        args.capture_dir.mkdir(parents=True, exist_ok=True)
        armed = [False]
        pending = {}
        paired = [0]

        def capture_gray(pad, info, kind):
            if not armed[0] or paired[0] >= args.compare_count:
                return Gst.PadProbeReturn.OK
            buffer = info.get_buffer()
            if buffer is None:
                return Gst.PadProbeReturn.OK
            pts = int(buffer.pts)
            if kind == "before":
                index = paired[0]
                pending[pts] = index
            elif pts in pending:
                index = pending.pop(pts)
            else:
                errors.append(f"Unmatched GREY frame PTS {pts}")
                GLib.idle_add(loop.quit)
                return Gst.PadProbeReturn.REMOVE
            ok, mapping = buffer.map(Gst.MapFlags.READ)
            if not ok:
                errors.append(f"Cannot map {kind} GREY frame")
                GLib.idle_add(loop.quit)
                return Gst.PadProbeReturn.REMOVE
            try:
                data = bytes(mapping.data)
            finally:
                buffer.unmap(mapping)
            # Keep capture probes short so the queue does not discard alternate
            # 60-fps frames while the diagnostic writes multi-megabyte files.
            compare_frames.append((kind, index, pts, data))
            if kind == "after":
                paired[0] += 1
                if paired[0] >= args.compare_count:
                    GLib.idle_add(loop.quit)
                    return Gst.PadProbeReturn.REMOVE
            return Gst.PadProbeReturn.OK

        pipeline.get_by_name("raw_input").get_static_pad("src").add_probe(
            Gst.PadProbeType.BUFFER,
            lambda pad, info: capture_gray(pad, info, "before"))
        pipeline.get_by_name("temporal").get_static_pad("src").add_probe(
            Gst.PadProbeType.BUFFER,
            lambda pad, info: capture_gray(pad, info, "after"))
        GLib.timeout_add(2200, lambda: (armed.__setitem__(0, True), False)[1])
        GLib.timeout_add_seconds(15, lambda: (loop.quit(), False)[1])

    try:
        state = pipeline.set_state(Gst.State.PLAYING)
        if state == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("Could not start HDMI pipeline")
        loop.run()
    finally:
        pipeline.set_state(Gst.State.NULL)
        pipeline.get_state(5 * Gst.SECOND)
    for kind, index, pts, data in compare_frames:
        path = args.capture_dir / f"{kind}_{index}.gray"
        path.write_bytes(data)
        print(f"COMPARE {index} {kind} PTS={pts} bytes={len(data)}", flush=True)
    if errors:
        print("; ".join(errors), flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

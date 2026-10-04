#!/usr/bin/env python3
"""Measure RK capture, conversion and overlay stages one at a time."""

import sys
import time

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst  # noqa: E402


Gst.init(None)
device = "/dev/video73"
use_kms = "--kms" in sys.argv
no_sync = "--kms-none" in sys.argv
nv12_kms = "--kms-nv12" in sys.argv
fast_kms = "--kms-fast" in sys.argv
source = (
    f"v4l2src device={device} io-mode=mmap "
    "! video/x-raw,format=GRAY8,width=1920,height=1080,framerate=60/1 "
)
reset_colorimetry = (
    '! capssetter caps="video/x-raw,format=(string)GRAY8,'
    'width=(int)1920,height=(int)1080,framerate=(fraction)60/1" replace=true '
)
convert_rgb = "! videoconvert n-threads=4 ! video/x-raw,format=RGBx "
text = (
    '! textoverlay text="HDMI 1920x1080 FPS:60" '
    'halignment=left valignment=top deltax=24 deltay=24 '
    'shaded-background=false font-desc="Sans Bold 18" '
)
sink = (
    "! fpsdisplaysink name=fps text-overlay=false silent=true "
    "sync=false video-sink=fakesink "
)
if use_kms or no_sync or nv12_kms or fast_kms:
    kmssink_options = "sync-mode=none" if no_sync else ""
    sink = (
        '! fpsdisplaysink name=fps text-overlay=false silent=true sync=false '
        'video-sink="kmssink connector-id=188 sync=false skip-vsync=true '
        + kmssink_options + '"'
    )
    cases = (
        ("kms_rgbx", source + reset_colorimetry + convert_rgb + sink, False),
        ("kms_static_text", source + reset_colorimetry + convert_rgb +
         text.replace("textoverlay text=", "textoverlay name=status text=") + sink,
         False),
        ("kms_dynamic_text", source + reset_colorimetry + convert_rgb +
         text.replace("textoverlay text=", "textoverlay name=status text=") + sink,
         True),
    )
    if no_sync:
        cases = cases[-1:]
    if nv12_kms:
        convert_nv12 = (
            "! videoconvert n-threads=4 ! video/x-raw,format=NV12 "
        )
        cases = (
            ("kms_nv12", source + reset_colorimetry + convert_nv12 + sink,
             False),
            ("kms_nv12_dynamic_text", source + reset_colorimetry +
             convert_nv12 +
             text.replace("textoverlay text=", "textoverlay name=status text=") +
             sink, True),
        )
    if fast_kms:
        cases = (("kms_fast_osd", source + reset_colorimetry + convert_rgb +
                  "! rkfastosd " + sink, False),)
else:
    cases = (
        ("capture", source + sink, False),
        ("rgbx_conversion", source + reset_colorimetry + convert_rgb + sink,
         False),
        ("rgbx_with_text", source + reset_colorimetry + convert_rgb + text +
         sink, False),
        ("nv12_conversion", source + reset_colorimetry +
         "! videoconvert n-threads=4 ! video/x-raw,format=NV12 " + sink,
         False),
    )

for name, description, dynamic_text in cases:
    pipeline = Gst.parse_launch(description)
    fps = pipeline.get_by_name("fps")
    try:
        if pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError(f"{name}: could not start")
        state = pipeline.get_state(5 * Gst.SECOND)
        if state.state != Gst.State.PLAYING:
            raise RuntimeError(f"{name}: state={state.state.value_nick}")
        t0 = time.monotonic()
        start = fps.get_property("frames-rendered")
        if dynamic_text:
            overlay = pipeline.get_by_name("status")
            for second in range(5):
                time.sleep(1)
                overlay.set_property("text", f"HDMI 1920x1080 FPS:{second}")
        else:
            time.sleep(5)
        elapsed = time.monotonic() - t0
        count = fps.get_property("frames-rendered") - start
        bus = pipeline.get_bus()
        error = bus.pop_filtered(Gst.MessageType.ERROR)
        if error:
            raise RuntimeError(f"{name}: {error.parse_error()[0]}")
        print(f"{name}: {count/elapsed:.2f} fps ({count} frames/{elapsed:.2f} s)",
              flush=True)
    finally:
        pipeline.set_state(Gst.State.NULL)
        pipeline.get_state(5 * Gst.SECOND)
    time.sleep(0.5)

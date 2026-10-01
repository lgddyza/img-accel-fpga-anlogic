"""Briefly compare RK HDMI rendering cost with and without text overlays."""

import time
import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst  # noqa: E402


Gst.init(None)
source = (
    "v4l2src device=/dev/video73 io-mode=mmap "
    "! video/x-raw,width=1920,height=1080,format=GRAY8 "
    "! queue max-size-buffers=4 max-size-bytes=0 max-size-time=0 leaky=downstream "
    "! videoconvert n-threads=4 ! video/x-raw,format=NV12 "
)
static_text = (
    '! textoverlay text="HDMI 1920x1080" halignment=left valignment=top '
    'deltax=24 deltay=24 shaded-background=true font-desc="Sans Bold 28" '
)
for name, text, fps_text in (
    ("conversion_only", "", False),
    ("fps_overlay", "", True),
    ("both_overlays", static_text, True),
):
    description = (
        source + text + "! fpsdisplaysink name=fps fps-update-interval=1000 "
        f"text-overlay={'true' if fps_text else 'false'} sync=false "
        'video-sink="kmssink connector-id=188 sync=false"'
    )
    pipeline = Gst.parse_launch(description)
    fps = pipeline.get_by_name("fps")
    try:
        result = pipeline.set_state(Gst.State.PLAYING)
        assert result != Gst.StateChangeReturn.FAILURE
        time.sleep(4)
        print(name, fps.get_property("last-message"),
              "rendered", fps.get_property("frames-rendered"), flush=True)
    finally:
        pipeline.set_state(Gst.State.NULL)
        pipeline.get_state(Gst.CLOCK_TIME_NONE)
    time.sleep(0.5)

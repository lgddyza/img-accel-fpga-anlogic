"""Capture buffers handed to RK kmssink after both HDMI text overlays.

Run on the RK board with the normal HDMI viewer stopped. This is a sink input
capture, not a photograph or DRM writeback of the physical connector.
"""

import time
from pathlib import Path

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst  # noqa: E402


Gst.init(None)
destination = Path("/dev/shm")
description = (
    "v4l2src device=/dev/video73 io-mode=mmap "
    "! video/x-raw,width=1920,height=1080,format=GRAY8 "
    "! queue max-size-buffers=4 max-size-bytes=0 max-size-time=0 leaky=downstream "
    "! videoconvert n-threads=4 ! video/x-raw,format=NV12 "
    "! videobalance brightness=0 contrast=1 "
    '! textoverlay text="HDMI 1920x1080" halignment=left valignment=top '
    'deltax=24 deltay=24 shaded-background=true font-desc="Sans Bold 28" '
    "! fpsdisplaysink name=fps fps-update-interval=1000 "
    "text-overlay=true sync=false "
    'video-sink="kmssink name=screen connector-id=188 sync=false"'
)
pipeline = Gst.parse_launch(description)
fps = pipeline.get_by_name("fps")
sink = fps.get_property("video-sink")
assert sink is not None
print("sink", sink.get_name(), flush=True)

try:
    state = pipeline.set_state(Gst.State.PLAYING)
    assert state != Gst.StateChangeReturn.FAILURE
    time.sleep(2.0)  # allow the FPS text to obtain its first measurement
    previous_pts = None
    for index in range(3):
        deadline = time.monotonic() + 5.0
        while True:
            sample = sink.get_property("last-sample")
            if sample is not None:
                buffer = sample.get_buffer()
                if buffer.pts != previous_pts:
                    break
            if time.monotonic() >= deadline:
                raise TimeoutError(f"No new HDMI sink sample {index}")
            time.sleep(0.02)
        ok, mapping = buffer.map(Gst.MapFlags.READ)
        if not ok:
            raise RuntimeError("Could not map HDMI sink sample")
        try:
            data = bytes(mapping.data)
        finally:
            buffer.unmap(mapping)
        (destination / f"hdmi_sink_{index}.raw").write_bytes(data)
        print(index, sample.get_caps().to_string(), len(data), buffer.pts, flush=True)
        previous_pts = buffer.pts
        time.sleep(0.2)
finally:
    pipeline.set_state(Gst.State.NULL)

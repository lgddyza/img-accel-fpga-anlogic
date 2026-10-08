#!/usr/bin/env python3
"""Check the AI HDMI status panel on two synthetic RGBx frames."""

import os
from pathlib import Path
import sys
import time

os.environ.setdefault("GST_PLUGIN_PATH", str(Path(__file__).resolve().parent))
os.environ["RK_AI_BOX_PATH"] = "/tmp/road_ai_boxes_status_test.bin"

from capture_jpeg_tiles import Gst
from show_jpeg_hdmi_overlay import OverlayState


def main():
    Gst.init(None)
    overlay = OverlayState(os.environ["RK_AI_BOX_PATH"])
    pipe = Gst.parse_launch(
        "appsrc name=source is-live=false format=bytes block=false "
        "caps=video/x-raw,format=RGBx,width=1920,height=1080,framerate=5/1 "
        "! rkstatusai ! appsink name=sink sync=false max-buffers=1 drop=false")
    source = pipe.get_by_name("source")
    sink = pipe.get_by_name("sink")
    image = bytes((128, 128, 128, 255)) * (1920 * 1080)

    def render():
        if source.emit("push-buffer", Gst.Buffer.new_wrapped(image)) != Gst.FlowReturn.OK:
            raise RuntimeError("OSD rejected test frame")
        sample = sink.emit("pull-sample")
        if not sample:
            raise RuntimeError("OSD returned no frame")
        buffer = sample.get_buffer()
        return buffer.extract_dup(0, buffer.get_size())

    try:
        if pipe.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("could not start the OSD")
        first = render()
        time.sleep(0.20)
        overlay.update([])
        second = render()
        stride = 1920 * 4
        bg = second[20 * stride + 20 * 4:20 * stride + 20 * 4 + 3]
        transparent = second[20 * stride + 21 * 4:20 * stride + 21 * 4 + 3]
        outside = second[20 * stride + 700 * 4:20 * stride + 700 * 4 + 3]
        if (bg != bytes((16, 40, 64)) or
                transparent != bytes((128, 128, 128)) or
                outside != bytes((128, 128, 128))):
            raise RuntimeError("50% transparent panel pixels are incorrect")
        if second[24 * stride + 26 * 4] != 255 or second[55 * stride + 26 * 4] != 255:
            raise RuntimeError("large status glyphs are missing")
        dynamic_before = first[55 * stride + 188 * 4:76 * stride + 250 * 4]
        dynamic_after = second[55 * stride + 188 * 4:76 * stride + 250 * 4]
        if dynamic_before == dynamic_after:
            raise RuntimeError("YOLO FPS did not change after an AI completion")
        print(f"STATUS_RENDER_OK shade_rgb={list(bg)} "
              f"pass_through_rgb={list(transparent)} dynamic_yolo_fps=updated")
    finally:
        pipe.set_state(Gst.State.NULL)
        overlay.close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        sys.exit(f"error: {error}")

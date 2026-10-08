#!/usr/bin/env python3
"""Check the RK GREY8 box/label renderer on one synthetic frame."""

import os
from pathlib import Path
import sys

os.environ.setdefault("GST_PLUGIN_PATH", str(Path(__file__).resolve().parent))
os.environ["RK_AI_BOX_PATH"] = "/tmp/road_ai_boxes_render_test.bin"

from capture_jpeg_tiles import Gst
from show_jpeg_hdmi_overlay import OverlayState


def main():
    Gst.init(None)
    overlay = OverlayState(os.environ["RK_AI_BOX_PATH"])
    overlay.update([(1, 0.87, 100, 100, 1000, 700)])
    pipe = Gst.parse_launch(
        "appsrc name=source is-live=false format=bytes block=false "
        "caps=video/x-raw,format=GRAY8,width=1920,height=1080,framerate=1/1 "
        "! rktemporalai fast-blend=true affine-blend=true "
        "! appsink name=sink sync=false max-buffers=1 drop=false")
    source = pipe.get_by_name("source")
    sink = pipe.get_by_name("sink")
    try:
        if pipe.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("could not start the renderer")
        image = bytes([128]) * (1920 * 1080)
        if source.emit("push-buffer", Gst.Buffer.new_wrapped(image)) != Gst.FlowReturn.OK:
            raise RuntimeError("renderer rejected test frame")
        sample = sink.emit("pull-sample")
        if not sample:
            raise RuntimeError("renderer returned no frame")
        buffer = sample.get_buffer()
        result = buffer.extract_dup(0, buffer.get_size())
        if (result[103 * 1920 + 500] != 255 or
                result[400 * 1920 + 500] != 128 or
                result[78 * 1920 + 300] != 0 or
                result[80 * 1920 + 104] != 255):
            raise RuntimeError("thick white box or original class label was not drawn")
        output = Path("/root/road_damage_yolov8n/overlay_renderer_test.pgm")
        output.write_bytes(b"P5\n1920 1080\n255\n" + result)
        print(f"OVERLAY_RENDER_OK {output} thick_white=255 "
              "label=Longitudinal_crack_0.87")
    finally:
        pipe.set_state(Gst.State.NULL)
        overlay.close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        sys.exit(f"error: {error}")

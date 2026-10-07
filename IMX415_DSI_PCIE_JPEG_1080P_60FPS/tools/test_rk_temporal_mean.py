#!/usr/bin/env python3
"""RK runtime check: HE phase changes stay stable even with a skipped phase."""

import os
from pathlib import Path

os.environ["GST_PLUGIN_PATH"] = str(Path(__file__).resolve().parent)

import gi  # noqa: E402

gi.require_version("Gst", "1.0")
from gi.repository import Gst  # noqa: E402


def main():
    Gst.init(None)
    width, height = 64, 64
    pipe = Gst.parse_launch(
        f"appsrc name=src is-live=false format=bytes caps=video/x-raw,"
        f"format=GRAY8,width={width},height={height},framerate=60/1 "
        "! rktemporalgray fast-blend=true "
        "! appsink name=sink sync=false max-buffers=1 drop=false"
    )
    src = pipe.get_by_name("src")
    sink = pipe.get_by_name("sink")
    inputs = [104, 132, 104, 132, 132, 104, 104, 132]
    outputs = []
    pipe.set_state(Gst.State.PLAYING)
    try:
        for value in inputs:
            payload = bytes([value]) * (width * height)
            buf = Gst.Buffer.new_allocate(None, len(payload), None)
            buf.fill(0, payload)
            if src.emit("push-buffer", buf) != Gst.FlowReturn.OK:
                raise RuntimeError("appsrc rejected input")
            sample = sink.emit("try-pull-sample", Gst.SECOND)
            if sample is None:
                raise RuntimeError("no filtered output")
            raw = sample.get_buffer().extract_dup(0, width * height)
            outputs.append(raw[0])
    finally:
        pipe.set_state(Gst.State.NULL)
    if max(outputs) - min(outputs) > 8:
        raise AssertionError(f"alternating output too large: {outputs}")
    print(f"TEMPORAL_MEAN_PASS input={inputs} output={outputs}")


if __name__ == "__main__":
    main()

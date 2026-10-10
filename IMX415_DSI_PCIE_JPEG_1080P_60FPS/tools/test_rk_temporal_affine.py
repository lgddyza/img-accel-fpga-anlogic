#!/usr/bin/env python3
"""Verify that RK affine blend suppresses alternating contrast at 60 FPS caps."""

import os
from pathlib import Path

os.environ["GST_PLUGIN_PATH"] = str(Path(__file__).resolve().parent)

import gi  # noqa: E402

gi.require_version("Gst", "1.0")
from gi.repository import Gst  # noqa: E402


def main():
    Gst.init(None)
    width, height = 128, 64
    pipeline = Gst.parse_launch(
        "appsrc name=src is-live=false format=bytes "
        f"caps=video/x-raw,format=GRAY8,width={width},height={height},framerate=60/1 "
        "! rktemporalgray fast-blend=true affine-blend=true "
        "! appsink name=sink sync=false max-buffers=1 drop=false"
    )
    source = pipeline.get_by_name("src")
    sink = pipeline.get_by_name("sink")
    measured = []
    pipeline.set_state(Gst.State.PLAYING)
    try:
        for index in range(12):
            low, high = ((60, 180), (50, 190))[index % 2]
            row = bytes(low + (high - low) * x // (width - 1)
                        for x in range(width))
            buffer = Gst.Buffer.new_wrapped(row * height)
            if source.emit("push-buffer", buffer) != Gst.FlowReturn.OK:
                raise RuntimeError("input rejected")
            sample = sink.emit("try-pull-sample", Gst.SECOND)
            if sample is None:
                raise RuntimeError("output missing")
            output = sample.get_buffer().extract_dup(0, width * height)
            measured.append((output[0], output[width - 1]))
    finally:
        pipeline.set_state(Gst.State.NULL)
    low_spread = max(pair[0] for pair in measured[4:]) - min(
        pair[0] for pair in measured[4:])
    high_spread = max(pair[1] for pair in measured[4:]) - min(
        pair[1] for pair in measured[4:])
    if max(low_spread, high_spread) > 5:
        raise AssertionError(f"contrast still alternates: {measured}")
    print(f"TEMPORAL_AFFINE_PASS edges={measured} spreads="
          f"({low_spread},{high_spread})")


if __name__ == "__main__":
    main()

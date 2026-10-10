#!/usr/bin/env python3
"""Capture three FPGA JPEG tiles and reconstruct 1920x1080 PGM snapshots.

Runs on RK3576 alongside the existing GREY HDMI viewer. Requires Python GI,
GStreamer v4l2src/appsink/jpegdec/videoconvert, and all three JPEG V4L2 modules.
"""

import argparse
from collections import deque
import os
import queue
import sys
import time
from pathlib import Path

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst

WIDTH = 1920
STRIPE = 8
HEIGHTS = (360, 360, 360)
PAIR_TOLERANCE_NS = 25_000_000


def find_devices():
    names = ("Milianke JPEG Tile A", "Milianke JPEG Tile B",
             "Milianke JPEG Tile C")
    result = {}
    for path in Path("/sys/class/video4linux").glob("video*/name"):
        try:
            name = path.read_text().strip()
        except OSError:
            continue
        if name in names:
            result[names.index(name)] = Path("/dev") / path.parent.name
    if len(result) != 3:
        raise RuntimeError("load milianke_jpeg_a.ko, milianke_jpeg_b.ko and milianke_jpeg_c.ko")
    return result[0], result[1], result[2]


def receiver(device, height, tile, output):
    # Resolve GI methods on the main thread before any of the three callback
    # threads starts; lazy introspection can race on this RK Python image.
    sample_get_buffer = Gst.Sample.get_buffer
    buffer_get_size = Gst.Buffer.get_size
    buffer_extract_dup = Gst.Buffer.extract_dup
    flow_ok = Gst.FlowReturn.OK
    flow_error = Gst.FlowReturn.ERROR
    pipe = Gst.parse_launch(
        f'v4l2src device="{device}" io-mode=mmap ! '
        f'image/jpeg,width={WIDTH},height={height} ! '
        'appsink name=jpeg_sink emit-signals=true max-buffers=4 drop=true sync=false'
    )
    sink = pipe.get_by_name("jpeg_sink")
    trace_count = 0
    trace_enabled = os.environ.get("JPEG_PAIR_TRACE") == "1"

    def on_sample(sink):
        nonlocal trace_count
        sample = sink.emit("pull-sample")
        if sample is None:
            return flow_error
        # Gst.Sample's GI instance method lookup is intermittent when the
        # three appsinks call back concurrently on this RK image. Resolve the
        # introspected method on the class instead.
        buf = sample_get_buffer(sample)
        trace_count += 1
        if trace_enabled and (trace_count <= 4 or trace_count % 600 == 0):
            try:
                print(f"JPEG DMA tile={tile} callback={trace_count} "
                      f"pts={buf.pts} offset={buf.offset} "
                      f"arrival_ns={time.monotonic_ns()}", flush=True)
            except (AttributeError, TypeError) as error:
                print(f"JPEG DMA tile={tile} metadata unavailable: {error}", flush=True)
        payload = buffer_extract_dup(buf, 0, buffer_get_size(buf))
        if not payload.startswith(b"\xff\xd8") or not payload.endswith(b"\xff\xd9"):
            return flow_ok
        # The three V4L2 sources have separate GStreamer clocks. Pair in the
        # shared process clock, which also avoids intermittent GI pts access
        # failures observed on this RK image under simultaneous callbacks.
        stamp = time.monotonic_ns()
        try:
            output.put_nowait((tile, int(stamp), payload))
        except queue.Full:
            pass
        return flow_ok

    sink.connect("new-sample", on_sample)
    return pipe


def decoder(height):
    pipe = Gst.parse_launch(
        'appsrc name=jpeg_src format=bytes is-live=false caps=image/jpeg ! '
        'jpegdec ! videoconvert ! '
        f'video/x-raw,format=GRAY8,width={WIDTH},height={height} ! '
        'appsink name=gray_sink sync=false max-buffers=1 drop=false'
    )
    return pipe, pipe.get_by_name("jpeg_src"), pipe.get_by_name("gray_sink")


def decode(src, sink, jpeg, height):
    buf = Gst.Buffer.new_allocate(None, len(jpeg), None)
    buf.fill(0, jpeg)
    if src.emit("push-buffer", buf) != Gst.FlowReturn.OK:
        raise RuntimeError("JPEG decoder rejected a tile")
    sample = sink.emit("try-pull-sample", 5 * Gst.SECOND)
    if sample is None:
        raise RuntimeError("JPEG decoder timed out")
    decoded = Gst.Sample.get_buffer(sample)
    raw = decoded.extract_dup(0, decoded.get_size())
    if len(raw) != WIDTH * height:
        raise RuntimeError(f"unexpected GRAY8 stride or size: {len(raw)}")
    return raw


def weave(a, b, c):
    out = bytearray(WIDTH * 1080)
    for stripe in range(135):
        source = (a, b, c)[stripe % 3]
        offset = (stripe // 3) * STRIPE * WIDTH
        target = stripe * STRIPE * WIDTH
        out[target:target + STRIPE * WIDTH] = source[offset:offset + STRIPE * WIDTH]
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=10)
    parser.add_argument("--output", type=Path, default=Path("jpeg_tiles"))
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    devices = find_devices()
    args.output.mkdir(parents=True, exist_ok=True)
    Gst.init(None)
    events = queue.Queue(maxsize=16)
    receivers = [receiver(devices[i], HEIGHTS[i], i, events) for i in range(3)]
    decoders = [decoder(HEIGHTS[i]) for i in range(3)]
    for pipe in receivers + [item[0] for item in decoders]:
        if pipe.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("could not start a JPEG capture/decoder pipeline")
    pending = [deque(), deque(), deque()]
    saved = 0
    received = [0, 0, 0]
    deadline = time.monotonic() + 10

    def incomplete_capture():
        for index, suffix in enumerate("abc"):
            if pending[index]:
                (args.output / f"unpaired_{suffix}.jpg").write_bytes(pending[index][-1][1])
        raise RuntimeError(f"waiting for paired JPEG tiles timed out; received A/B/C={received}")

    try:
        while saved < args.count:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                incomplete_capture()
            try:
                tile, stamp, payload = events.get(timeout=remaining)
            except queue.Empty:
                incomplete_capture()
            received[tile] += 1
            pending[tile].append((stamp, payload))
            if len(pending[tile]) > 4:
                pending[tile].popleft()
            while all(pending) and saved < args.count:
                stamps = [pending[i][0][0] for i in range(3)]
                if max(stamps) - min(stamps) > PAIR_TOLERANCE_NS:
                    pending[stamps.index(min(stamps))].popleft()
                    continue
                payloads = [pending[i].popleft()[1] for i in range(3)]
                grays = [decode(decoders[i][1], decoders[i][2],
                                payloads[i], HEIGHTS[i]) for i in range(3)]
                full = weave(*grays)
                stem = args.output / f"frame_{saved:05d}"
                for suffix, payload in zip("abc", payloads):
                    stem.with_suffix(f".{suffix}.jpg").write_bytes(payload)
                with stem.with_suffix(".pgm").open("wb") as fp:
                    fp.write(f"P5\n{WIDTH} 1080\n255\n".encode())
                    fp.write(full)
                print(f"{saved}: A/B/C={tuple(map(len, payloads))} full=1920x1080", flush=True)
                saved += 1
                deadline = time.monotonic() + 10
    finally:
        for pipe in receivers + [item[0] for item in decoders]:
            pipe.set_state(Gst.State.NULL)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        sys.exit(f"error: {error}")

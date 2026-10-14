#!/usr/bin/env python3
"""Capture three FPGA JPEG tiles and reconstruct 1920x1080 PGM snapshots.

Runs on RK3576 alongside the existing GREY HDMI viewer. Requires Python GI,
GStreamer v4l2src/appsink/jpegdec/videoconvert, and all three JPEG V4L2 modules.
"""

import argparse
import ctypes
import json
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
PAIR_TOLERANCE_NS = 6_000_000
CAPTURE_STATS = [dict(callbacks=0, invalid=0, queue_drops=0,
                      metadata_drops=0, sequence_gaps=0, payload_bytes=0,
                      telemetry_errors=0) for _ in range(3)]
_weave_path = Path(__file__).with_name('libjpeg_weave.so')
_weave_lib = ctypes.CDLL(str(_weave_path)) if _weave_path.exists() else None
if _weave_lib:
    _weave_lib.jpeg_weave_1080p.argtypes = [ctypes.c_void_p] * 4
    _weave_lib.jpeg_weave_1080p.restype = None
_jpeg_path = Path(__file__).with_name('libjpeg_native.so')
_jpeg_lib = ctypes.CDLL(str(_jpeg_path)) if _jpeg_path.exists() else None
if _jpeg_lib:
    _jpeg_lib.jpeg_decode_gray.argtypes = [ctypes.c_void_p, ctypes.c_size_t,
        ctypes.c_void_p, ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p, ctypes.c_size_t]
    _jpeg_lib.jpeg_decode_gray.restype = ctypes.c_int


class NativeJpegDecoder:
    def __init__(self, height):
        self.height = height
        self.output = ctypes.create_string_buffer(WIDTH * height)
        self.error = ctypes.create_string_buffer(256)

    def decode(self, jpeg):
        result = _jpeg_lib.jpeg_decode_gray(ctypes.c_char_p(jpeg), len(jpeg),
            self.output, WIDTH, self.height, self.error, len(self.error))
        if result:
            raise RuntimeError('JPEG decode: ' + self.error.value.decode(errors='replace'))
        return self.output.raw


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
    base_time = None
    previous_sequence = None
    stats = CAPTURE_STATS[tile]
    trace_enabled = os.environ.get("JPEG_PAIR_TRACE") == "1"
    telemetry_path = Path(f'/run/jpeg-rk-tile{tile}-telemetry.json')
    telemetry_temp = telemetry_path.with_suffix(f'.{os.getpid()}.tmp')
    last_telemetry = 0

    def on_sample(sink):
        nonlocal trace_count, base_time, previous_sequence, last_telemetry
        sample = sink.emit("pull-sample")
        if sample is None:
            return flow_error
        # Gst.Sample's GI instance method lookup is intermittent when the
        # three appsinks call back concurrently on this RK image. Resolve the
        # introspected method on the class instead.
        buf = sample_get_buffer(sample)
        trace_count += 1
        stats['callbacks'] += 1
        payload_size = buffer_get_size(buf)
        stats['payload_bytes'] += payload_size
        now = time.monotonic()
        if now-last_telemetry >= 1:
            try:
                telemetry_temp.write_text(json.dumps({'pid': os.getpid(), 'tile': tile,
                    'sample_s': now, 'frames': stats['callbacks'],
                    'payload_bytes': stats['payload_bytes']}))
                telemetry_temp.replace(telemetry_path)
            except OSError:
                stats['telemetry_errors'] += 1
            last_telemetry = now
        try:
            if base_time is None:
                base_time = pipe.get_base_time()
            pts, sequence = int(buf.pts), int(buf.offset)
            if pts == Gst.CLOCK_TIME_NONE or base_time == Gst.CLOCK_TIME_NONE:
                raise ValueError('missing capture timestamp')
            # v4l2src converts the driver's monotonic DMA timestamp to running
            # time. Restore absolute time to compare the independent pipelines.
            stamp = int(base_time) + pts
            if previous_sequence is not None and sequence > previous_sequence + 1:
                stats['sequence_gaps'] += sequence - previous_sequence - 1
            previous_sequence = sequence
        except (AttributeError, TypeError, ValueError):
            stats['metadata_drops'] += 1
            return flow_ok
        if trace_enabled and (trace_count <= 4 or trace_count % 600 == 0):
            try:
                print(f"JPEG DMA tile={tile} callback={trace_count} "
                      f"pts={pts} offset={sequence} capture_ns={stamp} "
                      f"arrival_ns={time.monotonic_ns()}", flush=True)
            except (AttributeError, TypeError) as error:
                print(f"JPEG DMA tile={tile} metadata unavailable: {error}", flush=True)
        payload = buffer_extract_dup(buf, 0, payload_size)
        if not payload.startswith(b"\xff\xd8") or not payload.endswith(b"\xff\xd9"):
            stats['invalid'] += 1
            return flow_ok
        try:
            output.put_nowait((tile, int(stamp), payload))
        except queue.Full:
            stats['queue_drops'] += 1
        return flow_ok

    sink.connect("new-sample", on_sample)
    return pipe


def decoder(height):
    if _jpeg_lib and os.environ.get('JPEG_NATIVE_DECODE', '1') != '0':
        # A placeholder pipeline keeps existing viewer start/stop ownership.
        return Gst.Pipeline.new(None), NativeJpegDecoder(height), None
    pipe = Gst.parse_launch(
        'appsrc name=jpeg_src format=bytes is-live=false caps=image/jpeg ! '
        'jpegdec ! videoconvert ! '
        f'video/x-raw,format=GRAY8,width={WIDTH},height={height} ! '
        'appsink name=gray_sink sync=false max-buffers=1 drop=false'
    )
    return pipe, pipe.get_by_name("jpeg_src"), pipe.get_by_name("gray_sink")


def decode(src, sink, jpeg, height):
    if isinstance(src, NativeJpegDecoder):
        return src.decode(jpeg)
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
    if any(len(tile) != WIDTH * 360 for tile in (a, b, c)):
        raise ValueError('weave requires three tightly packed 1920x360 tiles')
    out = bytearray(WIDTH * 1080)
    if _weave_lib and os.environ.get('JPEG_FAST_WEAVE', '1') != '0':
        target = (ctypes.c_ubyte * len(out)).from_buffer(out)
        _weave_lib.jpeg_weave_1080p(target, ctypes.c_char_p(a), ctypes.c_char_p(b), ctypes.c_char_p(c))
        return out
    target_view = memoryview(out)
    sources = tuple(memoryview(tile) for tile in (a, b, c))
    for stripe in range(135):
        source = sources[stripe % 3]
        offset = (stripe // 3) * STRIPE * WIDTH
        target = stripe * STRIPE * WIDTH
        target_view[target:target + STRIPE * WIDTH] = source[offset:offset + STRIPE * WIDTH]
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

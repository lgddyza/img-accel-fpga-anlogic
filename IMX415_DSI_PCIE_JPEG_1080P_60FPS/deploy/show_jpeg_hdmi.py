#!/usr/bin/env python3
"""Show the three FPGA JPEG tiles reconstructed as live 1080p HDMI video."""

import argparse
from collections import deque
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import queue
import signal
import sys
import time

from capture_jpeg_tiles import (Gst, HEIGHTS, PAIR_TOLERANCE_NS, WIDTH,
                                decode, decoder, find_devices, receiver, weave)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connector", type=int, default=188)
    parser.add_argument("--seconds", type=int, default=0,
                        help="0 keeps displaying until stopped")
    parser.add_argument("--capture-dir", type=Path,
                        help="save a few displayed GREY8 frames for inspection")
    parser.add_argument("--capture-count", type=int, default=3)
    parser.add_argument("--decoder", choices=("software", "mpp"), default="software")
    parser.add_argument("--decode-workers", type=int, choices=(1, 3), default=3)
    parser.add_argument("--fps", type=int, choices=(30, 60), default=30,
                        help="caps for the expected rate of distinct JPEG frames")
    parser.add_argument("--benchmark-repeat", type=int, choices=(1, 2), default=1,
                        help="repeat decoding the same tiles to load-test 60 FPS; frames are duplicates")
    parser.add_argument("--no-temporal", action="store_true",
                        help="disable the RK tone stabilizer for a controlled comparison")
    args = parser.parse_args()
    if args.connector < 0 or args.seconds < 0 or args.capture_count < 0:
        parser.error("connector, seconds and capture-count must be nonnegative")

    plugin_dirs = (Path(__file__).resolve().parent,
                   Path("/root/imx415_pcie_gray_1080p"))
    plugin_dir = next((path for path in plugin_dirs
                       if (path / "libgstrktemporalgray.so").is_file()), None)
    if not args.no_temporal and plugin_dir is None:
        raise RuntimeError("RK temporal GREY plugin is missing")
    if plugin_dir is not None:
        previous = os.environ.get("GST_PLUGIN_PATH", "")
        os.environ["GST_PLUGIN_PATH"] = str(plugin_dir) + (
            os.pathsep + previous if previous else "")
    Gst.init(None)
    # Force GI method resolution before the GStreamer and decoder workers race
    # to look up lazily introspected methods.
    _gi_methods = (Gst.Sample.get_buffer, Gst.Buffer.new_allocate,
                   Gst.Buffer.fill, Gst.Buffer.get_size, Gst.Buffer.extract_dup)
    devices = find_devices()
    events = queue.Queue(maxsize=24)
    receivers = [receiver(devices[i], HEIGHTS[i], i, events) for i in range(3)]
    if args.decoder == "software":
        decoders = [decoder(HEIGHTS[i]) for i in range(3)]
    else:
        decoders = []
        for height in HEIGHTS:
            pipe = Gst.parse_launch(
                'appsrc name=jpeg_src format=bytes is-live=false caps=image/jpeg '
                '! jpegparse ! mppjpegdec ! videoconvert '
                f'! video/x-raw,format=GRAY8,width={WIDTH},height={height} '
                '! appsink name=gray_sink sync=false max-buffers=1 drop=false'
            )
            decoders.append((pipe, pipe.get_by_name("jpeg_src"),
                             pipe.get_by_name("gray_sink")))
    display = Gst.parse_launch(
        'appsrc name=frames is-live=true format=time block=false '
        f'caps=video/x-raw,format=GRAY8,width=1920,height=1080,framerate={args.fps}/1 '
        '! queue max-size-buffers=2 max-size-bytes=0 max-size-time=0 leaky=downstream '
        + ('! rktemporalgray ' if not args.no_temporal else '')
        + '! videoconvert n-threads=4 ! video/x-raw,format=RGBx '
        '! fpsdisplaysink name=fps fps-update-interval=1000 '
        'text-overlay=false signal-fps-measurements=true silent=true sync=false '
        f'video-sink="kmssink connector-id={args.connector} '
        'sync=false skip-vsync=true"'
    )
    print(f"RK temporal GREY stabilizer: {'disabled' if args.no_temporal else 'enabled'}",
          flush=True)
    source = display.get_by_name("frames")
    source.set_property("do-timestamp", True)
    fps = display.get_by_name("fps")
    fps.connect("fps-measurements", lambda _obj, current, _dropped, _average:
                print(f"HDMI JPEG sink FPS={current:.1f}", flush=True))
    pending = [deque(), deque(), deque()]
    received = [0, 0, 0]
    mismatched = 0
    displayed = 0
    distinct = 0
    captured = 0
    requested_capture = False
    decode_ns = 0
    weave_ns = 0
    push_ns = 0
    stop = False

    def stopping(*_args):
        nonlocal stop
        stop = True

    def request_capture(*_args):
        nonlocal requested_capture
        requested_capture = True

    signal.signal(signal.SIGINT, stopping)
    signal.signal(signal.SIGTERM, stopping)
    signal.signal(signal.SIGUSR1, request_capture)
    pipes = receivers + [item[0] for item in decoders] + [display]
    executor = ThreadPoolExecutor(max_workers=args.decode_workers)
    started = time.monotonic()
    last_report = started
    if args.capture_dir:
        args.capture_dir.mkdir(parents=True, exist_ok=True)

    try:
        for pipe in pipes:
            if pipe.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
                raise RuntimeError("could not start a JPEG receiver, decoder or HDMI sink")
        while not stop and (not args.seconds or time.monotonic() - started < args.seconds):
            message = display.get_bus().pop_filtered(Gst.MessageType.ERROR)
            if message:
                error, detail = message.parse_error()
                raise RuntimeError(f"HDMI pipeline: {error}: {detail}")
            try:
                tile, stamp, payload = events.get(timeout=0.25)
            except queue.Empty:
                continue
            received[tile] += 1
            pending[tile].append((stamp, payload))
            if len(pending[tile]) > 3:
                pending[tile].popleft()
                mismatched += 1
            while all(pending):
                stamps = [pending[i][0][0] for i in range(3)]
                if max(stamps) - min(stamps) > PAIR_TOLERANCE_NS:
                    pending[stamps.index(min(stamps))].popleft()
                    mismatched += 1
                    continue
                payloads = [pending[i].popleft()[1] for i in range(3)]
                distinct += 1
                for _repeat in range(args.benchmark_repeat):
                    t0 = time.monotonic_ns()
                    if args.decode_workers == 3:
                        futures = [executor.submit(decode, decoders[i][1],
                                                   decoders[i][2], payloads[i],
                                                   HEIGHTS[i]) for i in range(3)]
                        grays = [future.result() for future in futures]
                    else:
                        grays = [decode(decoders[i][1], decoders[i][2],
                                        payloads[i], HEIGHTS[i]) for i in range(3)]
                    t1 = time.monotonic_ns()
                    full = weave(*grays)
                    t2 = time.monotonic_ns()
                    if args.capture_dir and (captured < args.capture_count or
                                             requested_capture):
                        path = args.capture_dir / f"jpeg_hdmi_{captured:03d}.pgm"
                        path.write_bytes(b"P5\n1920 1080\n255\n" + full)
                        captured += 1
                        requested_capture = False
                    buffer = Gst.Buffer.new_wrapped(bytes(full))
                    if source.emit("push-buffer", buffer) != Gst.FlowReturn.OK:
                        raise RuntimeError("HDMI appsrc rejected a reconstructed frame")
                    t3 = time.monotonic_ns()
                    decode_ns += t1 - t0
                    weave_ns += t2 - t1
                    push_ns += t3 - t2
                    displayed += 1
            now = time.monotonic()
            if now - last_report >= 5:
                print(f"elapsed={now-started:.1f}s received={received} "
                      f"reconstructed={displayed} unpaired={mismatched} "
                      f"distinct={distinct} rate={displayed/(now-started):.2f} fps "
                      f"ms/frame decode={decode_ns/max(displayed,1)/1e6:.1f} "
                      f"weave={weave_ns/max(displayed,1)/1e6:.1f} "
                      f"push={push_ns/max(displayed,1)/1e6:.1f}", flush=True)
                last_report = now
    finally:
        executor.shutdown(wait=True)
        for pipe in pipes:
            pipe.set_state(Gst.State.NULL)
        print(f"final elapsed={time.monotonic()-started:.1f}s received={received} "
              f"reconstructed={displayed} distinct={distinct} "
              f"unpaired={mismatched}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        sys.exit(f"error: {error}")

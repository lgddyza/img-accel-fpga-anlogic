#!/usr/bin/env python3
"""Keep the original FPGA HDMI video path and overlay asynchronous YOLO boxes."""

import argparse
import ctypes
from collections import deque
from concurrent.futures import ThreadPoolExecutor
import mmap
import os
from pathlib import Path
import queue
import signal
import struct
import sys
import time

from capture_jpeg_tiles import (CAPTURE_STATS, Gst, HEIGHTS, PAIR_TOLERANCE_NS, WIDTH,
                                decode, decoder, find_devices, receiver, weave)
from rk_video_fast import FramePusher


class RoadBox(ctypes.Structure):
    _fields_ = [("cls", ctypes.c_int), ("score", ctypes.c_float),
                ("x1", ctypes.c_float), ("y1", ctypes.c_float),
                ("x2", ctypes.c_float), ("y2", ctypes.c_float)]


class RoadDetector:
    def __init__(self, model, library):
        self.lib = ctypes.CDLL(str(library))
        self.lib.road_init.argtypes = [ctypes.c_char_p]
        self.lib.road_init.restype = ctypes.c_int
        self.lib.road_detect.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                                         ctypes.c_float, ctypes.POINTER(RoadBox), ctypes.c_int]
        self.lib.road_detect.restype = ctypes.c_int
        self.lib.road_error.restype = ctypes.c_char_p
        if self.lib.road_init(str(model).encode()) != 0:
            raise RuntimeError(self.lib.road_error().decode())

    def run(self, frame, confidence):
        # c_char_p keeps the immutable bytes alive during the C call.
        raw = ctypes.c_char_p(frame)
        results = (RoadBox * 300)()
        started = time.monotonic_ns()
        count = self.lib.road_detect(ctypes.cast(raw, ctypes.c_void_p),
                                     1920, 1080, confidence, results, 300)
        if count < 0:
            raise RuntimeError(self.lib.road_error().decode())
        boxes = [(int(b.cls), float(b.score), float(b.x1), float(b.y1),
                  float(b.x2), float(b.y2)) for b in results[:count]]
        return boxes, (time.monotonic_ns() - started) / 1e6

    def close(self):
        self.lib.road_close()


class OverlayState:
    SIZE = 1560
    MAX_BOXES = 64

    def __init__(self, path):
        fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            os.ftruncate(fd, self.SIZE)
            self.shared = mmap.mmap(fd, self.SIZE, access=mmap.ACCESS_WRITE)
        finally:
            os.close(fd)
        self.seq = 0
        struct.pack_into("<II", self.shared, 0, 0x52414942, 0)
        self.update([])

    def update(self, boxes):
        boxes = boxes[:self.MAX_BOXES]
        self.seq += 2
        struct.pack_into("<I", self.shared, 4, self.seq - 1)
        struct.pack_into("<QII", self.shared, 8,
                         time.monotonic_ns() // 1000, len(boxes), 0)
        for index, (cls, score, x1, y1, x2, y2) in enumerate(boxes):
            struct.pack_into("<fffffI", self.shared, 24 + index * 24,
                             x1, y1, x2, y2, score, cls)
        struct.pack_into("<I", self.shared, 4, self.seq)

    def close(self):
        self.update([])
        self.shared.close()


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
    parser.add_argument("--no-osd", action="store_true",
                        help="disable the live FPS and resolution overlay")
    parser.add_argument("--skip-vsync", action="store_true",
                        help="diagnostic: submit KMS frames without waiting for vblank")
    parser.add_argument("--diagnose-flicker", action="store_true",
                        help="log sampled decoded brightness and sudden jumps")
    parser.add_argument("--diagnose-pairing", action="store_true",
                        help="measure JPEG tile arrival skew and brightness mismatch")
    parser.add_argument("--clock-sync", action="store_true",
                        help="pace HDMI buffers with the GStreamer clock")
    parser.add_argument("--sink", choices=("kms", "xv"), default="kms",
                        help="HDMI presentation path; xv uses the running X11 desktop")
    parser.add_argument("--kms-sync-mode", choices=("auto", "flip", "vblank", "none"), default="auto",
                        help="KMS page-flip synchronization mode")
    parser.add_argument("--output-format", choices=("RGBx", "NV12"), default="RGBx",
                        help="pixel format sent to HDMI KMS plane")
    parser.add_argument("--temporal-method", choices=("blend", "affine", "tone", "normalize"),
                        default="normalize",
                        help="affine also stabilizes per-frame contrast at low cost")
    parser.add_argument("--ai-model", type=Path, required=True)
    parser.add_argument("--ai-library", type=Path,
                        default=Path(__file__).with_name("libroad_infer.so"))
    parser.add_argument("--ai-confidence", type=float, default=0.10)
    parser.add_argument("--ai-interval", type=int, default=6,
                        help="run AI on every Nth reconstructed frame; HDMI still gets every frame")
    args = parser.parse_args()
    if args.connector < 0 or args.seconds < 0 or args.capture_count < 0:
        parser.error("connector, seconds and capture-count must be nonnegative")
    if args.output_format != "RGBx":
        parser.error("the box overlay needs RGBx HDMI output")
    if args.no_temporal:
        parser.error("the AI overlay runs in the original temporal processing stage")
    if args.ai_interval < 1 or not 0 <= args.ai_confidence <= 1:
        parser.error("AI interval must be positive and confidence must be within [0,1]")
    detector = RoadDetector(args.ai_model, args.ai_library)
    overlay = OverlayState("/run/road_ai_boxes.bin")
    ai_executor = ThreadPoolExecutor(max_workers=1)
    ai_future = None
    ai_submitted = ai_completed = ai_ms = 0
    latest_boxes = 0

    plugin_dirs = (Path(__file__).resolve().parent / "active_ai_plugins",)
    temporal_plugin_dir = next((path for path in plugin_dirs
                                if (path / "libgstrktemporalai.so").is_file()), None)
    osd_plugin_dir = next((path for path in plugin_dirs
                           if (path / "libgstrkstatusai.so").is_file()), None)
    if not args.no_temporal and temporal_plugin_dir is None:
        raise RuntimeError("RK temporal GREY plugin is missing")
    if not args.no_osd and osd_plugin_dir is None:
        raise RuntimeError("RK fast OSD plugin is missing")
    active_plugin_dirs = []
    for path in (temporal_plugin_dir, osd_plugin_dir):
        if path is not None and path not in active_plugin_dirs:
            active_plugin_dirs.append(path)
    if active_plugin_dirs:
        os.environ["GST_PLUGIN_PATH"] = os.pathsep.join(
            str(path) for path in active_plugin_dirs)
    Gst.init(None)
    for element_name, expected_dir in (("rktemporalai", temporal_plugin_dir),
                                       ("rkstatusai", osd_plugin_dir)):
        if expected_dir is None:
            continue
        plugin = Gst.Registry.get().find_plugin(element_name)
        actual = Path(plugin.get_filename()).resolve() if plugin else None
        expected = (expected_dir / f"libgst{element_name}.so").resolve()
        if actual != expected:
            raise RuntimeError(f"{element_name} loaded from {actual}, expected {expected}")
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
    video_sink = (f'kmssink connector-id={args.connector} '
                  f'sync={str(args.clock_sync).lower()} '
                  f'sync-mode={args.kms_sync_mode} '
                  f'skip-vsync={str(args.skip_vsync).lower()}'
                  if args.sink == "kms" else
                  f'xvimagesink sync={str(args.clock_sync).lower()} '
                  'force-aspect-ratio=false double-buffer=true')
    display = Gst.parse_launch(
        'appsrc name=frames is-live=true format=time block=false '
        f'caps=video/x-raw,format=GRAY8,width=1920,height=1080,framerate={args.fps}/1 '
        '! queue name=display_queue max-size-buffers=3 max-size-bytes=0 '
        'max-size-time=0 leaky=downstream '
        + (f'! rktemporalai fast-blend={str(args.temporal_method != "tone").lower()} '
           f'affine-blend={str(args.temporal_method in ("affine", "normalize")).lower()} '
           f'mix-previous={str(args.temporal_method != "normalize").lower()} '
           if not args.no_temporal else '')
        + ('! rkstatusai name=status_osd ' if not args.no_osd else '')
        + f'! videoconvert n-threads=4 ! video/x-raw,format={args.output_format} '
        + ('! videoconvert n-threads=4 ! video/x-raw,format=I420 '
           if args.sink == "xv" else '')
        + '! queue name=present_queue max-size-buffers=2 max-size-bytes=0 '
        'max-size-time=0 leaky=downstream '
        + '! fpsdisplaysink name=fps fps-update-interval=1000 '
        'text-overlay=false signal-fps-measurements=true silent=true '
        f'sync={str(args.clock_sync).lower()} '
        f'video-sink="{video_sink}"'
    )
    temporal_status = "disabled" if args.no_temporal else args.temporal_method
    print(f"RK temporal GREY stabilizer: {temporal_status}", flush=True)
    print(f"RK HDMI status overlay: {'disabled' if args.no_osd else 'enabled'}",
          flush=True)
    print(f"RK KMS waits for vblank: {not args.skip_vsync}", flush=True)
    print(f"RK GStreamer clock pacing: {args.clock_sync}", flush=True)
    print(f"RK HDMI presentation sink: {args.sink}", flush=True)
    print(f"RK KMS sync mode: {args.kms_sync_mode}", flush=True)
    print(f"RK HDMI pixel format: {args.output_format}", flush=True)
    print(f"RK AI model: {args.ai_model} interval={args.ai_interval} "
          f"confidence={args.ai_confidence:.2f}", flush=True)
    source = display.get_by_name("frames")
    source.set_property("do-timestamp", True)
    pusher = FramePusher(source, Gst)
    print(f"HDMI native buffer push: {pusher.native}", flush=True)
    fps = display.get_by_name("fps")
    display_queue = display.get_by_name("display_queue")
    queue_overruns = [0]
    display_queue.connect("overrun", lambda _queue:
                          queue_overruns.__setitem__(0, queue_overruns[0] + 1))
    present_queue = display.get_by_name("present_queue")
    present_overruns = [0]
    present_queue.connect("overrun", lambda _queue:
                          present_overruns.__setitem__(0, present_overruns[0] + 1))
    status_osd = display.get_by_name("status_osd")

    def measured_fps(_obj, current, dropped, average):
        if status_osd is not None:
            status_osd.set_property("display-fps", current)
        print(f"HDMI JPEG sink FPS={current:.1f} dropped={dropped:.0f} "
              f"average={average:.1f}", flush=True)

    fps.connect("fps-measurements", measured_fps)
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
    previous_means = None
    skew_max_ns = 0
    skew_over_8 = 0
    skew_over_16 = 0
    tile_phase_mismatch = 0
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
                skew_ns = max(stamps) - min(stamps)
                skew_max_ns = max(skew_max_ns, skew_ns)
                skew_over_8 += skew_ns > 8_000_000
                skew_over_16 += skew_ns > 16_000_000
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
                    if args.diagnose_flicker or args.diagnose_pairing:
                        means = tuple(sum(tile[::4096]) // len(tile[::4096])
                                      for tile in grays)
                        if args.diagnose_pairing and max(means) - min(means) >= 18:
                            tile_phase_mismatch += 1
                            print(f"JPEG_TILE_PHASE_MISMATCH frame={distinct} "
                                  f"tile_means={means} arrival_skew_ms="
                                  f"{skew_ns/1e6:.2f}", flush=True)
                        if args.diagnose_flicker and (distinct <= 4 or distinct % 60 == 0 or
                                (previous_means is not None and
                                 any(abs(a-b) >= 20 for a, b in
                                     zip(means, previous_means)))):
                            print(f"JPEG decoded frame={distinct} tile_means={means} "
                                  f"previous={previous_means}", flush=True)
                        previous_means = means
                    t1 = time.monotonic_ns()
                    full = weave(*grays)
                    t2 = time.monotonic_ns()
                    if args.capture_dir and (captured < args.capture_count or
                                             requested_capture):
                        path = args.capture_dir / f"jpeg_hdmi_{captured:03d}.pgm"
                        path.write_bytes(b"P5\n1920 1080\n255\n" + full)
                        captured += 1
                        requested_capture = False
                    frame_bytes = bytes(full)
                    if pusher.push(frame_bytes) != int(Gst.FlowReturn.OK):
                        raise RuntimeError("HDMI appsrc rejected a reconstructed frame")
                    if ai_future is not None and ai_future.done():
                        boxes, elapsed_ai = ai_future.result()
                        overlay.update(boxes)
                        latest_boxes = len(boxes)
                        ai_completed += 1
                        ai_ms += elapsed_ai
                        ai_future = None
                    if ai_future is None and distinct % args.ai_interval == 0:
                        ai_future = ai_executor.submit(detector.run, frame_bytes,
                                                       args.ai_confidence)
                        ai_submitted += 1
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
                print(f"HDMI queue overruns={queue_overruns[0]} "
                      f"level={display_queue.get_property('current-level-buffers')}",
                      flush=True)
                print(f"JPEG_CAPTURE_STATS {CAPTURE_STATS}", flush=True)
                print(f"HDMI present overruns={present_overruns[0]} "
                      f"level={present_queue.get_property('current-level-buffers')}", flush=True)
                print(f"AI submitted={ai_submitted} completed={ai_completed} "
                      f"rate={ai_completed/(now-started):.2f} fps "
                      f"mean_ms={ai_ms/max(ai_completed,1):.2f} "
                      f"latest_boxes={latest_boxes}", flush=True)
                if args.diagnose_pairing:
                    print(f"JPEG_PAIR_DIAG frames={distinct} skew_max_ms="
                          f"{skew_max_ns/1e6:.2f} skew_gt8={skew_over_8} "
                          f"skew_gt16={skew_over_16} phase_mismatch="
                          f"{tile_phase_mismatch}", flush=True)
                last_report = now
    finally:
        executor.shutdown(wait=True)
        ai_executor.shutdown(wait=True)
        overlay.close()
        detector.close()
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

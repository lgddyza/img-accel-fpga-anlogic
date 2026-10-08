#!/usr/bin/env python3
"""Measure simultaneous raw GREY8 and three-lane JPEG PCIe payload rates."""

import argparse
import queue
import time
from pathlib import Path

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst

from preproc_mode import read32, user_bar

WIDTH = 1920
RAW_HEIGHT = 1080
JPEG_HEIGHT = 360


def find_devices():
    wanted = {
        "Milianke PCIe GREY": "raw",
        "Milianke JPEG Tile A": "jpeg_a",
        "Milianke JPEG Tile B": "jpeg_b",
        "Milianke JPEG Tile C": "jpeg_c",
    }
    found = {}
    for name_file in Path("/sys/class/video4linux").glob("video*/name"):
        try:
            key = wanted.get(name_file.read_text().strip())
        except OSError:
            continue
        if key:
            found[key] = str(Path("/dev") / name_file.parent.name)
    missing = sorted(set(wanted.values()) - set(found))
    if missing:
        raise RuntimeError(f"missing V4L2 devices: {', '.join(missing)}")
    return found


def fpga_snapshot():
    offsets = {
        "width": 0x44,
        "height": 0x48,
        "raw_bytes": 0x58,
        "abi": 0x5C,
        "raw_drops": 0x68,
        "raw_delivered": 0x70,
        "raw_beats": 0x78,
        "raw_faults": 0x94,
        "preproc_mode": 0xA4,
        "jpeg_abi": 0xB0,
        "jpeg_quality": 0xB8,
        "jpeg_a_sent": 0xBC,
        "jpeg_b_sent": 0xC0,
        "jpeg_faults": 0xCC,
        "jpeg_c_sent": 0xDC,
        "jpeg_rate": 0xF0,
        "jpeg_signature": 0xF4,
    }
    bar, _ = user_bar()
    try:
        return {name: read32(bar, offset) for name, offset in offsets.items()}
    finally:
        bar.close()


def make_receiver(device, kind, events, callback_drops):
    sample_get_buffer = Gst.Sample.get_buffer
    buffer_get_size = Gst.Buffer.get_size
    buffer_extract_dup = Gst.Buffer.extract_dup
    flow_ok = Gst.FlowReturn.OK
    flow_error = Gst.FlowReturn.ERROR
    if kind == "raw":
        caps = f"video/x-raw,format=GRAY8,width={WIDTH},height={RAW_HEIGHT},framerate=60/1"
    else:
        caps = f"image/jpeg,width={WIDTH},height={JPEG_HEIGHT}"
    pipe = Gst.parse_launch(
        f'v4l2src device="{device}" io-mode=mmap ! {caps} ! '
        f'appsink name=sink emit-signals=true max-buffers=8 drop=true sync=false'
    )
    sink = pipe.get_by_name("sink")

    def on_sample(sink):
        sample = sink.emit("pull-sample")
        if sample is None:
            return flow_error
        buf = sample_get_buffer(sample)
        size = buffer_get_size(buf)
        valid = True
        if kind != "raw":
            valid = (size >= 4 and
                     buffer_extract_dup(buf, 0, 2) == b"\xff\xd8" and
                     buffer_extract_dup(buf, size - 2, 2) == b"\xff\xd9")
        try:
            events.put_nowait((kind, size, valid))
        except queue.Full:
            callback_drops[kind] += 1
        return flow_ok

    sink.connect("new-sample", on_sample)
    return pipe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=60.0)
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")

    Gst.init(None)
    devices = find_devices()
    events = queue.Queue(maxsize=8192)
    callback_drops = {key: 0 for key in devices}
    pipes = [make_receiver(devices[key], key, events, callback_drops)
             for key in ("raw", "jpeg_a", "jpeg_b", "jpeg_c")]
    count = {key: 0 for key in devices}
    total = {key: 0 for key in devices}
    low = {key: 2**63 - 1 for key in devices}
    high = {key: 0 for key in devices}
    invalid = {key: 0 for key in devices}
    before = fpga_snapshot()
    started = time.monotonic()
    deadline = started + args.seconds
    try:
        for pipe in pipes:
            if pipe.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
                raise RuntimeError("could not start all four capture pipelines")
        next_report = started + 15
        while time.monotonic() < deadline:
            try:
                kind, size, valid = events.get(timeout=0.2)
            except queue.Empty:
                continue
            count[kind] += 1
            total[kind] += size
            low[kind] = min(low[kind], size)
            high[kind] = max(high[kind], size)
            if not valid:
                invalid[kind] += 1
            now = time.monotonic()
            if now >= next_report:
                print(f"progress elapsed={now-started:.1f}s count={count}", flush=True)
                next_report += 15
    finally:
        for pipe in pipes:
            pipe.set_state(Gst.State.NULL)
    elapsed = time.monotonic() - started
    after = fpga_snapshot()

    print(f"elapsed_seconds={elapsed:.3f}")
    for key in ("raw", "jpeg_a", "jpeg_b", "jpeg_c"):
        average = total[key] / count[key] if count[key] else 0
        minimum = low[key] if count[key] else 0
        print(f"stream={key} frames={count[key]} fps={count[key]/elapsed:.3f} "
              f"bytes_total={total[key]} bytes_min={minimum} "
              f"bytes_avg={average:.1f} bytes_max={high[key]} "
              f"payload_mbps={total[key]*8/elapsed/1_000_000:.3f} "
              f"invalid={invalid[key]} callback_drops={callback_drops[key]}")
    jpeg_frames = min(count[key] for key in ("jpeg_a", "jpeg_b", "jpeg_c"))
    jpeg_average = sum(total[key] / count[key]
                       for key in ("jpeg_a", "jpeg_b", "jpeg_c") if count[key])
    raw_average = total["raw"] / count["raw"] if count["raw"] else 0
    jpeg_total = sum(total[key] for key in ("jpeg_a", "jpeg_b", "jpeg_c"))
    print(f"combined_jpeg_frames={jpeg_frames} combined_bytes_avg={jpeg_average:.1f} "
          f"combined_payload_mbps={jpeg_total*8/elapsed/1_000_000:.3f} "
          f"compression_ratio={raw_average/jpeg_average if jpeg_average else 0:.3f}")
    print(f"all_four_payload_mbps={(total['raw']+jpeg_total)*8/elapsed/1_000_000:.3f}")
    print(f"fpga_before={before}")
    print(f"fpga_after={after}")

    if (min(count.values()) == 0 or any(invalid.values()) or
            any(callback_drops.values()) or after["jpeg_faults"] or
            after["raw_faults"]):
        raise RuntimeError("stream measurement detected missing, invalid, dropped, or faulty data")


if __name__ == "__main__":
    main()

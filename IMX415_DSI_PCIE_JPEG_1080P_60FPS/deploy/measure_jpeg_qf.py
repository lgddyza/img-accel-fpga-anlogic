#!/usr/bin/env python3
"""Measure live three-tile FPGA JPEG sizes at each QF on RK3576.

Run with no other JPEG V4L2 consumer. Saves one complete A/B/C sample per
quality, restores the original QF, and leaves the frame-rate register alone.
"""

import argparse
from collections import deque
import json
from pathlib import Path
import queue
import statistics
import time

from capture_jpeg_tiles import Gst, HEIGHTS, find_devices
from jpeg_control import (JPEG_CONTROL_ABI, REG_APPLIED_QUALITY,
                          REG_CONTROL_ABI, REG_FAULTS, REG_QUALITY,
                          REG_RATE_MODE, REG_SENT_A, REG_SENT_B, REG_SENT_C,
                          wait_for_quality)
from preproc_mode import read32, user_bar, write32

QUALITIES = (30, 40, 50, 60, 70, 80, 90)
RAW_BYTES = 1920 * 1080


def make_receiver(device, tile, events):
    pipe = Gst.parse_launch(
        f'v4l2src device="{device}" io-mode=mmap ! '
        f'image/jpeg,width=1920,height={HEIGHTS[tile]} ! '
        'appsink name=sink emit-signals=true max-buffers=8 drop=true sync=false'
    )
    sink = pipe.get_by_name('sink')
    sample_get_buffer = Gst.Sample.get_buffer
    buffer_get_size = Gst.Buffer.get_size
    buffer_extract_dup = Gst.Buffer.extract_dup

    def on_sample(sink):
        sample = sink.emit('pull-sample')
        if sample is None:
            return Gst.FlowReturn.ERROR
        buf = sample_get_buffer(sample)
        payload = buffer_extract_dup(buf, 0, buffer_get_size(buf))
        if payload.startswith(b'\xff\xd8') and payload.endswith(b'\xff\xd9'):
            try:
                events.put_nowait((tile, int(buf.offset), payload))
            except queue.Full:
                pass
        return Gst.FlowReturn.OK

    sink.connect('new-sample', on_sample)
    return pipe


def percentile(values, percent):
    ordered = sorted(values)
    index = round((len(ordered) - 1) * percent / 100)
    return ordered[index]


def collect(events, count, timeout):
    pending = {}
    complete = []
    deadline = time.monotonic() + timeout
    first = None
    while len(complete) < count:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError(f'paired frames {len(complete)}/{count} before timeout')
        try:
            tile, frame_id, payload = events.get(timeout=min(remaining, 1))
        except queue.Empty:
            continue
        parts = pending.setdefault(frame_id, {})
        parts[tile] = payload
        if len(parts) == 3:
            if first is None:
                first = time.monotonic()
            complete.append(tuple(parts[i] for i in range(3)))
            del pending[frame_id]
            if len(complete) == 1:
                print(f'first paired offset={frame_id}', flush=True)
        if len(pending) > 96:
            for old in sorted(pending)[:len(pending) - 64]:
                del pending[old]
    return complete, time.monotonic() - first


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--frames', type=int, default=180)
    parser.add_argument('--settle-frames', type=int, default=45)
    parser.add_argument('--output', type=Path, default=Path('/run/qf_live'))
    args = parser.parse_args()
    if args.frames < 30 or args.settle_frames < 10:
        parser.error('need at least 30 measured and 10 settling frames')
    args.output.mkdir(parents=True, exist_ok=True)
    Gst.init(None)
    bar, bar_path = user_bar()
    original = read32(bar, REG_QUALITY)
    if read32(bar, REG_CONTROL_ABI) != JPEG_CONTROL_ABI:
        raise RuntimeError('JCT1 applied-QF readback is required')
    if read32(bar, REG_RATE_MODE) != 1:
        raise RuntimeError('set JPEG rate to 60 while capture is stopped')
    events = queue.Queue(maxsize=4096)
    devices = find_devices()
    pipes = [make_receiver(devices[i], i, events) for i in range(3)]
    results = []
    initial_faults = read32(bar, REG_FAULTS)
    try:
        for pipe in pipes:
            if pipe.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
                raise RuntimeError('V4L2 JPEG pipeline could not start')
        for quality in QUALITIES:
            write32(bar, REG_QUALITY, quality)
            wait_for_quality(bar, quality, True, 2.0)
            # Discard queued packets and all frames still crossing the QF
            # update boundary before beginning this quality's measurement.
            while not events.empty():
                events.get_nowait()
            collect(events, args.settle_frames, 8)
            while not events.empty():
                events.get_nowait()
            frames, elapsed = collect(events, args.frames, 12)
            sizes = [sum(map(len, triple)) for triple in frames]
            per_tile = [[len(triple[i]) for triple in frames] for i in range(3)]
            # In this fixed indoor scene the darker lamp phase produces a
            # larger JPEG. Keep the lower-byte phase for a visually fairer
            # cross-QF montage; the measured statistics still use all frames.
            sample = min(frames, key=lambda triple: sum(map(len, triple)))
            for name, payload in zip('abc', sample):
                (args.output / f'qf{quality}_{name}.jpg').write_bytes(payload)
            requested = read32(bar, REG_QUALITY)
            applied = read32(bar, REG_APPLIED_QUALITY)
            result = {
                'qf': quality, 'requested': requested,
                'applied': applied & 0x7f, 'applied_valid': bool(applied & 0x80),
                'frames': len(frames), 'elapsed_s': round(elapsed, 3),
                'receive_fps': round((len(frames) - 1) / elapsed, 2),
                'min_bytes': min(sizes),
                'p05_bytes': percentile(sizes, 5),
                'median_bytes': percentile(sizes, 50),
                'mean_bytes': round(statistics.mean(sizes)),
                'p95_bytes': percentile(sizes, 95),
                'max_bytes': max(sizes),
                'tile_mean_bytes': [round(statistics.mean(s)) for s in per_tile],
                'sample_tile_bytes': [len(p) for p in sample],
                'raw_to_jpeg_ratio': round(RAW_BYTES / statistics.mean(sizes), 2),
                'mbps_at_60fps': round(statistics.mean(sizes) * 60 * 8 / 1e6, 2),
                'fpga_sent': [read32(bar, r) for r in
                              (REG_SENT_A, REG_SENT_B, REG_SENT_C)],
                'fpga_faults': read32(bar, REG_FAULTS),
            }
            results.append(result)
            print(json.dumps(result), flush=True)
            (args.output / 'metrics.json').write_text(json.dumps({
                'meaning': 'actual FPGA JPEG tiles over PCIe, QF changed live',
                'resolution': [1920, 1080], 'raw_gray8_bytes': RAW_BYTES,
                'rate_setting_fps': 60, 'initial_qf': original,
                'initial_faults': initial_faults, 'bar': str(bar_path),
                'results': results}, indent=2) + '\n')
    finally:
        for pipe in pipes:
            pipe.set_state(Gst.State.NULL)
        write32(bar, REG_QUALITY, original)
        wait_for_quality(bar, original, True, 2.0)
        print(f'restored QF={original} faults={read32(bar, REG_FAULTS)}',
              flush=True)
        bar.close()


if __name__ == '__main__':
    main()

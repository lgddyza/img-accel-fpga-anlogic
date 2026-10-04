#!/usr/bin/env python3
"""Count three live JPEG streams without saving frames on the RK3576."""

import argparse
import queue
import time

from capture_jpeg_tiles import Gst, HEIGHTS, find_devices, receiver
from preproc_mode import read32, user_bar


def fpga_counts():
    bar, _ = user_bar()
    try:
        return tuple(read32(bar, offset) for offset in (0xBC, 0xC0, 0xDC, 0xCC))
    finally:
        bar.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=120)
    args = parser.parse_args()
    if args.seconds < 1:
        parser.error("--seconds must be positive")

    Gst.init(None)
    events = queue.Queue(maxsize=1024)
    devices = find_devices()
    pipes = [receiver(devices[i], HEIGHTS[i], i, events) for i in range(3)]
    count = [0, 0, 0]
    total = [0, 0, 0]
    low = [2**31, 2**31, 2**31]
    high = [0, 0, 0]
    started = time.monotonic()
    deadline = started + args.seconds
    try:
        for pipe in pipes:
            if pipe.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
                raise RuntimeError("could not start a JPEG receiver")
        next_report = started + 15
        while time.monotonic() < deadline:
            try:
                tile, _, payload = events.get(timeout=0.5)
            except queue.Empty:
                continue
            length = len(payload)
            count[tile] += 1
            total[tile] += length
            low[tile] = min(low[tile], length)
            high[tile] = max(high[tile], length)
            if time.monotonic() >= next_report:
                print(f"elapsed={time.monotonic()-started:.1f}s received={count} "
                      f"FPGA A/B/C/faults={fpga_counts()}", flush=True)
                next_report += 15
    finally:
        for pipe in pipes:
            pipe.set_state(Gst.State.NULL)

    elapsed = time.monotonic() - started
    print(f"final elapsed={elapsed:.1f}s received={count} "
          f"fps={[round(c / elapsed, 2) for c in count]} "
          f"bytes_min={[n if n != 2**31 else 0 for n in low]} "
          f"bytes_avg={[round(total[i] / count[i]) if count[i] else 0 for i in range(3)]} "
          f"bytes_max={high} FPGA A/B/C/faults={fpga_counts()}", flush=True)
    if min(count) == 0 or max(count) - min(count) > 2 or fpga_counts()[3] != 0:
        raise RuntimeError("JPEG stream counts diverged or FPGA reported a fault")


if __name__ == "__main__":
    main()

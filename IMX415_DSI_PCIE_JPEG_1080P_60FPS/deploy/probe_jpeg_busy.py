#!/usr/bin/env python3
"""Measure JPEG busy/idle intervals of the currently programmed FPGA."""

import argparse
import statistics
import time

from preproc_mode import read32, user_bar


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=3)
    args = parser.parse_args()
    bar, _ = user_bar()
    intervals = {False: [], True: []}
    transitions = []
    try:
        began = time.monotonic_ns()
        current = bool(read32(bar, 0xB4) & 4)
        segment_start = began
        while time.monotonic_ns() - began < args.seconds * 1e9:
            now = time.monotonic_ns()
            state = bool(read32(bar, 0xB4) & 4)
            if state != current:
                intervals[current].append((now - segment_start) / 1e6)
                transitions.append((round((now - began) / 1e6, 2),
                                    int(state), read32(bar, 0xBC),
                                    read32(bar, 0x50)))
                segment_start = now
                current = state
            time.sleep(0.0001)
        for state in (False, True):
            values = intervals[state]
            if values:
                print(f"{'busy' if state else 'idle'} count={len(values)} "
                      f"min/median/max_ms={min(values):.3f}/"
                      f"{statistics.median(values):.3f}/{max(values):.3f}")
        print("first transitions (ms, busy, jpeg_sent_a, gray_captured):")
        for item in transitions[:30]:
            print(item)
    finally:
        bar.close()


if __name__ == "__main__":
    main()

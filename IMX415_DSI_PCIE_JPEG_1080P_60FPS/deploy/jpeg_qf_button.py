#!/usr/bin/env python3
"""Use the RK-side K1 button to cycle FPGA JPEG QF over the PCIe BAR.

K1 is active low on RK3576 GPIO1_B7 (Linux GPIO 47) on MLK-AFH03.
Run --probe-seconds first to confirm that the fitted button toggles 1/0/1.
"""

import argparse
import fcntl
import signal
import sys
import time
from pathlib import Path

from jpeg_control import (JPEG_CONTROL_ABI, REG_CONTROL_ABI, REG_FAULTS,
                          REG_QUALITY, REG_STATUS, wait_for_quality)
from preproc_mode import read32, user_bar, write32


PRESETS = (30, 40, 50, 60, 70, 80, 90)
GPIO = 47
DEBOUNCE_SECONDS = 0.06
POLL_SECONDS = 0.02


def gpio_value_path(number):
    path = Path(f"/sys/class/gpio/gpio{number}")
    if not path.exists():
        Path("/sys/class/gpio/export").write_text(str(number))
        for _ in range(50):
            if path.exists():
                break
            time.sleep(0.01)
    if not path.exists():
        raise RuntimeError(f"GPIO {number} could not be exported")
    (path / "direction").write_text("in")
    return path / "value"


def next_quality(current):
    return next((quality for quality in PRESETS if quality > current), PRESETS[0])


def run(args):
    value_path = gpio_value_path(args.gpio)
    region = None
    lock = None
    if args.probe_seconds == 0:
        lock = open("/run/jpeg_qf_button.lock", "w")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError("another QF button controller is running") from exc
        region, bar_path = user_bar()
        if read32(region, REG_CONTROL_ABI) != JPEG_CONTROL_ABI:
            raise RuntimeError("JCT1 bitstream is required for verified button control")
        print(f"K1 GPIO={args.gpio} BAR={bar_path} presets={PRESETS}", flush=True)
    else:
        print(f"Probing GPIO {args.gpio} for {args.probe_seconds:g} seconds", flush=True)

    stop = False

    def stopping(_signal, _frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, stopping)
    signal.signal(signal.SIGTERM, stopping)
    try:
        stable = int(value_path.read_text().strip())
        candidate = stable
        candidate_since = time.monotonic()
        print(f"initial GPIO={stable}", flush=True)
        deadline = (time.monotonic() + args.probe_seconds
                    if args.probe_seconds else float("inf"))
        while not stop and time.monotonic() < deadline:
            now = time.monotonic()
            value = int(value_path.read_text().strip())
            if value != candidate:
                candidate = value
                candidate_since = now
            if candidate != stable and now - candidate_since >= DEBOUNCE_SECONDS:
                stable = candidate
                print(f"K1 {'pressed' if stable == 0 else 'released'} GPIO={stable}",
                      flush=True)
                if stable == 0 and region is not None:
                    current = read32(region, REG_QUALITY)
                    target = next_quality(current)
                    try:
                        write32(region, REG_QUALITY, target)
                        applied, verified = wait_for_quality(region, target, True, 1.0)
                        status = read32(region, REG_STATUS)
                        faults = read32(region, REG_FAULTS)
                        if not verified or not (status & 8) or (status & 16) or faults:
                            raise RuntimeError(f"status=0x{status:x} faults={faults}")
                        print(f"QF {current} -> {applied} verified", flush=True)
                    except (OSError, RuntimeError) as exc:
                        print(f"QF {current} -> {target} failed: {exc}",
                              file=sys.stderr, flush=True)
            time.sleep(POLL_SECONDS)
    finally:
        if region is not None:
            region.close()
        if lock is not None:
            lock.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gpio", type=int, default=GPIO)
    parser.add_argument("--probe-seconds", type=float, default=0,
                        help="observe K1 transitions without changing QF")
    args = parser.parse_args()
    if args.gpio < 0 or args.probe_seconds < 0:
        parser.error("GPIO and probe duration must be nonnegative")
    run(args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as exc:
        sys.exit(f"error: {exc}")

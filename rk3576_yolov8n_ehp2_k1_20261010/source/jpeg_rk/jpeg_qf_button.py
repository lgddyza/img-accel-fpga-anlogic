#!/usr/bin/env python3
"""K1: short release cycles JPEG QF; long hold cycles preprocessing.

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
from preproc_mode import (CLAHE_TAG, ENHANCE_TAG, ENHANCE2_TAG, REG_ALGORITHM,
                          REG_MODE, REG_APPLIED_MODE, REG_OVERRUN,
                          read32, user_bar, write32)


PRESETS = (30, 40, 50, 60, 70, 80, 90)
GPIO = 47
DEBOUNCE_SECONDS = 0.06
POLL_SECONDS = 0.02
LONG_PRESS_SECONDS = 1.2
MODE_NAMES = ("GRAY", "GAUSS", "CLAHE", "GAUSS+CLAHE", "SOBEL",
              "BLACKHAT", "SOBEL+CLAHE", "BLACKHAT+CLAHE")


class K1Press:
    """Debounce active-low input and emit one short/long action per press."""
    def __init__(self, level, now, long_seconds=LONG_PRESS_SECONDS):
        self.stable = self.candidate = level
        self.candidate_since = now
        self.pressed_at = None
        self.long_fired = False
        self.armed = level != 0  # Ignore a key held when the service starts.
        self.long_seconds = long_seconds

    def update(self, level, now):
        if level != self.candidate:
            self.candidate = level
            self.candidate_since = now
        action = None
        if self.candidate != self.stable and now-self.candidate_since >= DEBOUNCE_SECONDS:
            self.stable = self.candidate
            if self.stable == 0 and self.armed:
                self.pressed_at = self.candidate_since
                self.long_fired = False
            elif self.stable == 1:
                if self.pressed_at is not None and not self.long_fired:
                    duration = self.candidate_since-self.pressed_at
                    action = "long" if duration >= self.long_seconds else "short"
                self.pressed_at = None
                self.long_fired = False
                self.armed = True
        if (self.stable == 0 and self.candidate == 0 and self.pressed_at is not None
                and not self.long_fired and now-self.pressed_at >= self.long_seconds):
            self.long_fired = True
            action = "long"
        return action


def next_mode(current, bitmap):
    choices = [mode for mode in range(8) if bitmap & (1 << mode)]
    if not choices:
        raise RuntimeError("No supported preprocessing modes")
    return next((mode for mode in choices if mode > current), choices[0])


def cycle_preprocessing(region):
    tag = read32(region, REG_ALGORITHM)
    if tag == ENHANCE2_TAG:
        bitmap = read32(region, 0x104) & 0xff
    elif tag == ENHANCE_TAG:
        bitmap = 0x3f
    elif tag == CLAHE_TAG:
        bitmap = 0x0f
    else:
        raise RuntimeError("Verified preprocessing capability tag unavailable")
    current = read32(region, REG_APPLIED_MODE)
    target = next_mode(current, bitmap)
    write32(region, REG_MODE, target)
    if read32(region, REG_MODE) != target:
        raise RuntimeError("Preprocessing request did not latch")
    deadline = time.monotonic() + 1.0
    while read32(region, REG_APPLIED_MODE) != target:
        if time.monotonic() >= deadline:
            raise RuntimeError("Camera did not apply preprocessing within one second")
        time.sleep(0.005)
    if read32(region, REG_OVERRUN) & 1:
        raise RuntimeError("Preprocessing fault after switch")
    print(f"PREPROC {current} {MODE_NAMES[current] if current < 8 else 'UNKNOWN'}"
          f" -> {target} {MODE_NAMES[target]} verified", flush=True)
    return target


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
            raise RuntimeError("another K1 button controller is running") from exc
        region, bar_path = user_bar()
        if read32(region, REG_CONTROL_ABI) != JPEG_CONTROL_ABI:
            raise RuntimeError("JCT1 bitstream is required for verified button control")
        print(f"K1 GPIO={args.gpio} BAR={bar_path} short=QF presets={PRESETS} "
              f"long={args.long_press_seconds:g}s PREPROC, once per hold", flush=True)
    else:
        print(f"Probing GPIO {args.gpio} for {args.probe_seconds:g} seconds", flush=True)

    stop = False

    def stopping(_signal, _frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, stopping)
    signal.signal(signal.SIGTERM, stopping)
    try:
        press = K1Press(int(value_path.read_text().strip()), time.monotonic(),
                        args.long_press_seconds)
        print(f"initial GPIO={press.stable}", flush=True)
        deadline = (time.monotonic() + args.probe_seconds
                    if args.probe_seconds else float("inf"))
        while not stop and time.monotonic() < deadline:
            now = time.monotonic()
            value = int(value_path.read_text().strip())
            previous = press.stable
            action = press.update(value, now)
            if press.stable != previous:
                print(f"K1 {'pressed' if press.stable == 0 else 'released'} GPIO={press.stable}", flush=True)
            if action and region is not None:
                if action == "long":
                    try:
                        cycle_preprocessing(region)
                    except (OSError, RuntimeError) as exc:
                        print(f"PREPROC failed: {exc}", file=sys.stderr, flush=True)
                else:
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
    parser.add_argument("--long-press-seconds", type=float, default=LONG_PRESS_SECONDS,
                        help="hold duration to cycle preprocessing once (default 1.2s)")
    args = parser.parse_args()
    if args.gpio < 0 or args.probe_seconds < 0 or args.long_press_seconds < 0.3:
        parser.error("GPIO/probe duration must be nonnegative and long press at least 0.3s")
    run(args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as exc:
        sys.exit(f"error: {exc}")

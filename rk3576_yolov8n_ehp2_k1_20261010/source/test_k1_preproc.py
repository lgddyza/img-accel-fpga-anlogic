"""Run on RK: verify debounce/hold semantics, optional live BAR switching."""
import argparse
import json
import os
from pathlib import Path
import sys
import time

sys.path.insert(0, "/root/jpeg_rk")
sys.path.insert(0, os.environ.get("K1_SCRIPT_DIR", "/root/jpeg_rk"))
from jpeg_qf_button import K1Press, next_mode, cycle_preprocessing
from preproc_mode import read32, write32, user_bar, REG_MODE, REG_APPLIED_MODE


def actions(events, initial=1):
    key = K1Press(initial, 0)
    found = []
    for now, level in events:
        action = key.update(level, now)
        if action:
            found.append(action)
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--save", type=Path)
    args = parser.parse_args()
    cases = {
        "short_release": ([(.1,0),(.17,0),(.4,1),(.47,1)], 1, ["short"]),
        "hold_once_release_no_qf": ([(.1,0),(.17,0),(1.31,0),(2.5,0),(5,0),(5.1,1),(5.17,1)], 1, ["long"]),
        "press_bounce": ([(.1,0),(.12,1),(.14,0),(.22,0),(.4,1),(.48,1)], 1, ["short"]),
        "glitch_ignored": ([(.1,0),(.12,1),(.2,1)], 1, []),
        "startup_held_ignored": ([(2,0),(3,1),(3.08,1),(4,0),(4.08,0),(4.4,1),(4.48,1)], 0, ["short"]),
        "late_poll_release_long": ([(.1,0),(.17,0),(1.5,1),(1.57,1)], 1, ["long"]),
        "two_distinct_holds": ([(.1,0),(.17,0),(1.31,0),(1.5,1),(1.57,1),
                                (2,0),(2.08,0),(3.21,0),(3.4,1),(3.48,1)], 1, ["long","long"]),
    }
    report = {"logic": {}}
    for name, (events, initial, expected) in cases.items():
        actual = actions(events, initial)
        assert actual == expected, (name, actual, expected)
        report["logic"][name] = actual
    assert [next_mode(m, 0xff) for m in range(8)] == [1,2,3,4,5,6,7,0]
    assert next_mode(7, 0x15) == 0 and next_mode(0, 0x15) == 2
    if args.live:
        region, path = user_bar()
        initial_mode = read32(region, REG_APPLIED_MODE)
        quality = read32(region, 0xb8)
        report["bar"] = str(path)
        report["initial_mode"] = initial_mode
        report["switches"] = []
        try:
            for _ in range(8):
                target = cycle_preprocessing(region)
                # Allow the 1Hz status plane to show every actual mode.
                time.sleep(1.15)
                state = {"applied": read32(region, REG_APPLIED_MODE),
                         "qf": read32(region, 0xb8),
                         "preproc_fault": read32(region, 0xa8),
                         "raw_fault": read32(region, 0x94),
                         "jpeg_fault": read32(region, 0xcc)}
                assert state["applied"] == target and state["qf"] == quality
                assert not any(state[k] for k in ("preproc_fault","raw_fault","jpeg_fault"))
                report["switches"].append(state)
            assert read32(region, REG_APPLIED_MODE) == initial_mode
        finally:
            write32(region, REG_MODE, initial_mode)
            region.close()
    if args.save:
        args.save.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()

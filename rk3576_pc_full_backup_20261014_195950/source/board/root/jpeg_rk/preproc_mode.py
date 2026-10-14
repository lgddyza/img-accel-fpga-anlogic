#!/usr/bin/env python3
"""Read or set the preprocessing mode through the FPGA PCIe user BAR.

Run as root on the RK3576 only after programming the preprocessing candidate.
The existing GREY8 V4L2 driver may remain loaded. No third-party modules.
"""

import argparse
import mmap
import os
from pathlib import Path
import struct
import sys
import time


PCI_ROOT = Path("/sys/bus/pci/devices")
VENDOR, DEVICE = "0x1edb", "0xabcd"
ABI, WIDTH, HEIGHT = 0x47520005, 1920, 1080
REG_MODE, REG_OVERRUN = 0xA4, 0xA8
REG_ALGORITHM, REG_APPLIED_MODE = 0xAC, 0x100
CLAHE_TAG = 0x434C4831  # CLH1
ENHANCE_TAG = 0x45485031  # EHP1
ENHANCE2_TAG = 0x45485032  # EHP2
REGION_SIZE = 0x1000
MODES = {"gray": 0, "gauss": 1, "he": 2, "all": 3,
         "clahe": 2, "gauss-clahe": 3, "sobel": 4, "blackhat": 5,
         "sobel-clahe": 6, "blackhat-clahe": 7}


def read32(region, offset):
    return struct.unpack_from("<I", region, offset)[0]


def write32(region, offset, value):
    struct.pack_into("<I", region, offset, value)


def user_bar():
    errors = []
    for device in PCI_ROOT.glob("*"):
        try:
            if (device / "vendor").read_text().strip().lower() != VENDOR:
                continue
            if (device / "device").read_text().strip().lower() != DEVICE:
                continue
        except OSError:
            continue
        for number in range(6):
            path = device / f"resource{number}"
            if not path.exists():
                continue
            try:
                fd = os.open(path, os.O_RDWR | getattr(os, "O_SYNC", 0))
                try:
                    region = mmap.mmap(fd, REGION_SIZE, access=mmap.ACCESS_WRITE)
                finally:
                    os.close(fd)
                if (read32(region, 0x5C), read32(region, 0x44),
                        read32(region, 0x48)) == (ABI, WIDTH, HEIGHT):
                    return region, path
                region.close()
            except (OSError, ValueError) as exc:
                errors.append(f"{path}: {exc}")
    details = "; ".join(errors) if errors else "no matching PCIe BAR"
    raise RuntimeError(f"ABI 5 GREY endpoint unavailable: {details}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", nargs="?", choices=(*MODES, "status"),
                        default="status")
    parser.add_argument("--wait-applied", action="store_true",
                        help="wait for a camera frame to latch the new mode (CLH1/EHP1/EHP2)")
    args = parser.parse_args()
    region, path = user_bar()
    try:
        tag = read32(region, REG_ALGORITHM)
        has_enhance = tag in (ENHANCE_TAG, ENHANCE2_TAG)
        has_combinations = tag == ENHANCE2_TAG
        has_clahe = tag in (CLAHE_TAG, ENHANCE_TAG, ENHANCE2_TAG)
        if args.mode in ("sobel-clahe", "blackhat-clahe") and not has_combinations:
            raise RuntimeError("enhancement followed by CLAHE requires the EHP2 FPGA image")
        if args.mode in ("sobel", "blackhat") and not has_enhance:
            raise RuntimeError("Sobel/blackhat require an EHP1 or EHP2 FPGA image")
        if args.mode in ("clahe", "gauss-clahe") and not has_clahe:
            raise RuntimeError("CLAHE capability tag absent; current FPGA image may use legacy HE")
        if args.mode == "he" and has_clahe:
            raise RuntimeError("this FPGA image implements CLAHE; select 'clahe' instead")
        if args.wait_applied and not has_clahe:
            raise RuntimeError("applied-mode feedback requires a CLH1/EHP1/EHP2 FPGA image")
        if args.mode != "status":
            # The previous board-verified bitstream also reports ABI 5 but
            # does not implement a writable mode register. Probe both values
            # so a read-only status register cannot masquerade as this one.
            if not has_clahe:
                for probe in (1, 2):
                    write32(region, REG_MODE, probe)
                    if read32(region, REG_MODE) != probe:
                        raise RuntimeError("mode register did not respond; check FPGA bitstream")
            write32(region, REG_MODE, MODES[args.mode])
            if read32(region, REG_MODE) != MODES[args.mode]:
                raise RuntimeError("requested mode did not latch in the PCIe register")
            if args.wait_applied:
                deadline = time.monotonic() + 2.0
                while read32(region, REG_APPLIED_MODE) != MODES[args.mode]:
                    if time.monotonic() >= deadline:
                        raise RuntimeError("camera did not latch mode within two seconds")
                    time.sleep(0.005)
        value = read32(region, REG_MODE)
        if value > (7 if has_combinations else 5 if has_enhance else 3):
            raise RuntimeError(f"invalid mode register value 0x{value:08x}")
        names = ("gray", "gauss", "clahe", "gauss+clahe") if has_clahe else (
            "gray", "gauss", "legacy HE or unknown", "gauss+legacy HE or unknown")
        if has_enhance:
            names += ("Sobel guided T1 gain0.5", "directional blackhat K3 gain1 line5" if has_combinations
                      else "directional blackhat K7 gain0.5 line5")
        if has_combinations:
            names += ("Sobel followed by CLAHE", "blackhat K3 gain1 followed by CLAHE")
        print(f"BAR: {path}")
        print(f"algorithm ABI: {'EHP2 (shared K3/gain1, post-CLAHE)' if has_combinations else 'EHP1 (CLAHE/Sobel/blackhat)' if has_enhance else 'CLH1 (2x2 CLAHE)' if has_clahe else 'unknown/legacy'}")
        print(f"mode requested: {value} ({names[value]})")
        if has_clahe:
            applied = read32(region, REG_APPLIED_MODE)
            print(f"mode applied: {applied} ({names[applied] if applied < len(names) else 'invalid'})")
        print(f"preprocessing overrun/alignment fault: {read32(region, REG_OVERRUN) & 1}")
    finally:
        region.close()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, PermissionError) as exc:
        sys.exit(f"error: {exc}")

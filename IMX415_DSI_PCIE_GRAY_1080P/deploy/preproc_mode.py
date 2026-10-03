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


PCI_ROOT = Path("/sys/bus/pci/devices")
VENDOR, DEVICE = "0x1edb", "0xabcd"
ABI, WIDTH, HEIGHT = 0x47520005, 1920, 1080
REG_MODE, REG_OVERRUN = 0xA4, 0xA8
REGION_SIZE = 0x1000
MODES = {"gray": 0, "gauss": 1, "he": 2, "all": 3}


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
    args = parser.parse_args()
    region, path = user_bar()
    try:
        if args.mode != "status":
            # The previous board-verified bitstream also reports ABI 5 but
            # does not implement a writable mode register. Probe both values
            # so a read-only status register cannot masquerade as this one.
            for probe in (1, 2):
                write32(region, REG_MODE, probe)
                if read32(region, REG_MODE) != probe:
                    raise RuntimeError("mode register did not respond; check FPGA bitstream")
            write32(region, REG_MODE, MODES[args.mode])
        value = read32(region, REG_MODE)
        if value > 3:
            raise RuntimeError(f"invalid mode register value 0x{value:08x}")
        names = [name for name, number in MODES.items() if number == value]
        print(f"BAR: {path}")
        print(f"mode: {value} ({names[0]})")
        print(f"Gaussian padding overrun: {read32(region, REG_OVERRUN) & 1}")
    finally:
        region.close()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, PermissionError) as exc:
        sys.exit(f"error: {exc}")

#!/usr/bin/env python3
"""Inspect or set FPGA JPEG quality and frame selection rate on RK3576.

Change quality or rate while JPEG streaming is stopped. The GREY channel may
remain active. New-bit JP60 capability is required for the rate selection.
"""

import argparse
import sys

from preproc_mode import read32, user_bar, write32


JPEG_ABI = 0x3347504A
REG_ABI = 0xB0
REG_STATUS = 0xB4
REG_QUALITY = 0xB8
REG_SENT_A = 0xBC
REG_SENT_B = 0xC0
REG_BYTES_A = 0xC4
REG_BYTES_B = 0xC8
REG_FAULTS = 0xCC
REG_MAX_BYTES = 0xD0
REG_HEIGHT_A = 0xD4
REG_HEIGHT_B = 0xD8
REG_SENT_C = 0xDC
REG_BYTES_C = 0xE0
REG_HEIGHT_C = 0xE4
REG_DEBUG = 0xE8
REG_DETAIL = 0xEC
REG_RATE_MODE = 0xF0
REG_FEATURES = 0xF4
JPEG_60_FEATURE = 0x4A503630


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("quality", nargs="?", type=int,
                        help="JPEG quality from 1 to 100; omit for status")
    parser.add_argument("--rate", type=int, choices=(30, 60),
                        help="select full-frame rate on a JP60-capable bitstream")
    args = parser.parse_args()
    if args.quality is not None and not 1 <= args.quality <= 100:
        parser.error("quality must be 1..100")

    region, path = user_bar()
    try:
        if read32(region, REG_ABI) != JPEG_ABI:
            raise RuntimeError("JPEG triple-tile ABI 3 is absent; program the new bitstream")
        status = read32(region, REG_STATUS)
        supports_60 = read32(region, REG_FEATURES) == JPEG_60_FEATURE
        if args.rate is not None:
            if not supports_60:
                raise RuntimeError("current bitstream lacks JP60 rate control")
            if status & 1:
                raise RuntimeError("stop JPEG capture before changing rate")
            write32(region, REG_RATE_MODE, int(args.rate == 60))
            if read32(region, REG_RATE_MODE) != int(args.rate == 60):
                raise RuntimeError("JPEG rate register did not accept the value")
        if args.quality is not None:
            if status & 1:
                raise RuntimeError("stop JPEG capture before changing quality")
            write32(region, REG_QUALITY, args.quality)
            if read32(region, REG_QUALITY) != args.quality:
                raise RuntimeError("quality register did not accept the value")
        status = read32(region, REG_STATUS)
        print(f"BAR: {path}")
        print(f"quality: {read32(region, REG_QUALITY)}")
        print(f"rate mode: {30 + 30 * read32(region, REG_RATE_MODE)} FPS"
              if supports_60 else "rate mode: fixed 30 FPS (old bitstream)")
        print(f"enable={status & 1} dma_ready={(status >> 1) & 1} "
              f"busy={(status >> 2) & 1} configured={(status >> 3) & 1} "
              f"fault={(status >> 4) & 1}")
        print(f"A: height={read32(region, REG_HEIGHT_A)} "
              f"sent={read32(region, REG_SENT_A)} "
              f"last_bytes={read32(region, REG_BYTES_A)}")
        print(f"B: height={read32(region, REG_HEIGHT_B)} "
              f"sent={read32(region, REG_SENT_B)} "
              f"last_bytes={read32(region, REG_BYTES_B)}")
        print(f"C: height={read32(region, REG_HEIGHT_C)} "
              f"sent={read32(region, REG_SENT_C)} "
              f"last_bytes={read32(region, REG_BYTES_C)}")
        print(f"faults={read32(region, REG_FAULTS)} "
              f"max_bytes={read32(region, REG_MAX_BYTES)}")
        debug = read32(region, REG_DEBUG)
        if debug:
            print("debug bits (LSB=A, B, MSB=C): "
                  f"bridge_fault={(debug >> 0) & 7:03b} "
                  f"packer_fault={(debug >> 3) & 7:03b} "
                  f"configured={(debug >> 6) & 7:03b} "
                  f"input_seen={(debug >> 9) & 7:03b} "
                  f"jpeg_byte_seen={(debug >> 12) & 7:03b} "
                  f"jpeg_eoi_seen={(debug >> 15) & 7:03b}")
            detail = read32(region, REG_DETAIL)
            print("first input fault: "
                  f"C_cause=0x{detail & 15:x} "
                  f"C_line={(detail >> 4) & 1023} "
                  f"C_beat={(detail >> 14) & 1023} "
                  f"B_cause=0x{(detail >> 24) & 15:x} "
                  f"A_cause=0x{(detail >> 28) & 15:x} "
                  "(cause: bit0=new SOF, bit1=bad EOL, "
                  "bit2=extra line, bit3=FIFO full)")
    finally:
        region.close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, PermissionError) as exc:
        sys.exit(f"error: {exc}")

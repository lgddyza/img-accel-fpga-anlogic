#!/usr/bin/env python3
"""Inspect or set FPGA JPEG quality and frame selection rate on RK3576.

Quality can be changed between frames with --live. Rate changes still require
stopped JPEG capture. New-bit JP60 capability is required for rate selection.
"""

import argparse
import sys
import time

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
REG_APPLIED_QUALITY = 0xF8
REG_CONTROL_ABI = 0xFC
JPEG_60_FEATURE = 0x4A503630
JPEG_CONTROL_ABI = 0x4A435431
QUALITY_PRESETS = (30, 40, 50, 60, 70, 80, 90)


def wait_for_quality(region, quality, control_abi, timeout):
    deadline = time.monotonic() + timeout
    # Legacy bitstreams do not expose the applied value. Give all three
    # encoder update FSMs ample time, then require their combined ready bit.
    if not control_abi:
        time.sleep(min(0.05, timeout))
    while time.monotonic() < deadline:
        status = read32(region, REG_STATUS)
        requested = read32(region, REG_QUALITY)
        if control_abi:
            applied_reg = read32(region, REG_APPLIED_QUALITY)
            applied_valid = bool(applied_reg & 0x80)
            applied = applied_reg & 0x7F
            if requested == quality and applied_valid and applied == quality:
                return applied, True
        elif requested == quality and status & (1 << 3):
            return quality, False
        time.sleep(0.002)
    raise RuntimeError(f"timed out waiting for JPEG QF {quality} to apply")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("legacy_quality", nargs="?", type=int,
                        help="legacy positional JPEG quality from 1 to 100")
    parser.add_argument("--quality", type=int,
                        help="JPEG quality from 1 to 100; recommended presets: "
                             + ", ".join(map(str, QUALITY_PRESETS)))
    parser.add_argument("--rate", type=int, choices=(30, 60),
                        help="select full-frame rate on a JP60-capable bitstream")
    parser.add_argument("--live", action="store_true",
                        help="apply quality between frames while capture remains active")
    parser.add_argument("--timeout", type=float, default=1.0,
                        help="seconds to wait for all three encoders (default: 1.0)")
    args = parser.parse_args()
    if args.legacy_quality is not None and args.quality is not None:
        parser.error("use either positional quality or --quality, not both")
    quality = args.quality if args.quality is not None else args.legacy_quality
    if quality is not None and not 1 <= quality <= 100:
        parser.error("quality must be 1..100")
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    if args.live and quality is None:
        parser.error("--live requires a quality value")

    region, path = user_bar()
    try:
        if read32(region, REG_ABI) != JPEG_ABI:
            raise RuntimeError("JPEG triple-tile ABI 3 is absent; program the new bitstream")
        status = read32(region, REG_STATUS)
        supports_60 = read32(region, REG_FEATURES) == JPEG_60_FEATURE
        control_abi = read32(region, REG_CONTROL_ABI) == JPEG_CONTROL_ABI
        if args.rate is not None:
            if not supports_60:
                raise RuntimeError("current bitstream lacks JP60 rate control")
            if status & 1:
                raise RuntimeError("stop JPEG capture before changing rate")
            write32(region, REG_RATE_MODE, int(args.rate == 60))
            if read32(region, REG_RATE_MODE) != int(args.rate == 60):
                raise RuntimeError("JPEG rate register did not accept the value")
        applied = None
        if quality is not None:
            if status & 1 and not args.live:
                raise RuntimeError("stop JPEG capture or add --live before changing quality")
            write32(region, REG_QUALITY, quality)
            if read32(region, REG_QUALITY) != quality:
                raise RuntimeError("quality register did not accept the value")
            applied, _ = wait_for_quality(region, quality, control_abi,
                                          args.timeout)
        status = read32(region, REG_STATUS)
        print(f"BAR: {path}")
        requested = read32(region, REG_QUALITY)
        print(f"quality requested: {requested}")
        if control_abi:
            applied_reg = read32(region, REG_APPLIED_QUALITY)
            valid = bool(applied_reg & 0x80)
            value = applied_reg & 0x7F
            print(f"quality applied: {value if valid else 'updating'} (verified)")
        elif applied is not None:
            print(f"quality applied: {applied} (legacy settle inference)")
        elif status & (1 << 3):
            print(f"quality applied: {requested} (legacy ready inference)")
        else:
            print("quality applied: unavailable (legacy bitstream)")
        print(f"control ABI: {'JCT1' if control_abi else 'legacy'}")
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

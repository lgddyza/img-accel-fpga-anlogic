#!/usr/bin/env python3
"""Run on RK: inspect/calibrate FPGA DSI independently of PCIe image processing."""
import argparse
import json
import sys
import time


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--bayer', choices=['auto', 'RGGB', 'GBRG', 'BGGR', 'GRBG'])
    ap.add_argument('--filter', choices=['on', 'off'])
    ap.add_argument('--bars', choices=['on', 'off'])
    ap.add_argument('--restore-default', action='store_true')
    args = ap.parse_args()
    sys.path.insert(0, '/root/jpeg_rk')
    from preproc_mode import read32, write32, user_bar

    region, path = user_bar()
    try:
        tag = read32(region, 0x108)
        if tag != 0x44433136:
            raise SystemExit(f'DC16 bit required; register 0x108 is 0x{tag:08x}. Nothing written.')
        old = read32(region, 0x10c)
        control = 0 if args.restore_default else old
        if args.bayer is not None:
            control = (control & ~7) | {'auto': 0, 'RGGB': 1, 'GBRG': 3,
                                        'BGGR': 5, 'GRBG': 7}[args.bayer]
        if args.filter is not None:
            control = (control & ~8) | (8 if args.filter == 'off' else 0)
        if args.bars is not None:
            control = (control & ~16) | (16 if args.bars == 'on' else 0)
        if control != old:
            write32(region, 0x10c, control)
            time.sleep(0.10)  # frame-boundary application + scanout delay
        status = read32(region, 0x110)
        print(json.dumps({'bar': str(path), 'build': 'DC16',
            'control': f'0x{read32(region, 0x10c):02x}',
            'automatic_phase': not bool(control & 1),
            'retained_sensor_row_odd': bool(status & 4),
            'applied_phase_flip': bool(status & 1),
            'applied_swap_rb': bool(status & 2),
            'filter': 'off' if control & 8 else 'on',
            'bars': bool(control & 16)}, indent=2))
    finally:
        region.close()


if __name__ == '__main__':
    main()

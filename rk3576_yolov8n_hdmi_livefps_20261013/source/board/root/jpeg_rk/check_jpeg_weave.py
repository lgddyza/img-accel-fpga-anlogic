#!/usr/bin/env python3
"""Check reconstructed PGM dimensions and 8-row JPEG stripe boundaries."""

import argparse
from pathlib import Path

WIDTH, HEIGHT = 1920, 1080


def inspect(path):
    parts = path.read_bytes().split(b"\n", 3)
    if len(parts) != 4 or parts[:3] != [b"P5", b"1920 1080", b"255"]:
        raise ValueError(f"bad PGM header: {path}")
    pixels = parts[3]
    if len(pixels) != WIDTH * HEIGHT:
        raise ValueError(f"bad PGM size: {path}: {len(pixels)}")

    seam = [[], [], []]
    interior = []
    view = memoryview(pixels)
    for row in range(HEIGHT - 1):
        first = view[row * WIDTH:(row + 1) * WIDTH:32]
        second = view[(row + 1) * WIDTH:(row + 2) * WIDTH:32]
        difference = sum(abs(a - b) for a, b in zip(first, second)) / len(first)
        if row % 8 == 7:
            seam[(row // 8) % 3].append(difference)
        else:
            interior.append(difference)
    return [sum(values) / len(values) for values in seam], sum(interior) / len(interior)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    paths = sorted(args.directory.glob("frame_*.pgm"))
    if not paths:
        parser.error("no reconstructed PGM files")
    results = [inspect(path) for path in paths]
    seam_mean = [sum(item[0][i] for item in results) / len(results) for i in range(3)]
    interior_mean = sum(item[1] for item in results) / len(results)
    print(f"PGM files={len(paths)} size={WIDTH}x{HEIGHT} "
          f"mean_abs_row_difference: interior={interior_mean:.2f} "
          f"A/B={seam_mean[0]:.2f} B/C={seam_mean[1]:.2f} "
          f"C/A={seam_mean[2]:.2f}")


if __name__ == "__main__":
    main()

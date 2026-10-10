"""Summarize successive full GREY8 camera frames captured with v4l2-ctl."""

import argparse
from pathlib import Path
import statistics

WIDTH = 1920
HEIGHT = 1080
FRAME_BYTES = WIDTH * HEIGHT


def samples():
    positions = []
    regions = []
    for y in range(16, HEIGHT, 32):
        for x in range(32, WIDTH, 64):
            positions.append(y * WIDTH + x)
            regions.append((y >= HEIGHT // 2) * 2 + (x >= WIDTH // 2))
    return positions, regions


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("frames", type=Path)
    args = parser.parse_args()
    size = args.frames.stat().st_size
    if size % FRAME_BYTES:
        parser.error(f"file is not an integer number of 1080p GREY8 frames: {size}")

    positions, regions = samples()
    means = []
    quadrants = []
    pair_diffs = []
    previous = None
    with args.frames.open("rb") as stream:
        for _ in range(size // FRAME_BYTES):
            frame = stream.read(FRAME_BYTES)
            pixels = [frame[index] for index in positions]
            means.append(statistics.mean(pixels))
            quadrants.append(tuple(statistics.mean(p for p, r in zip(pixels, regions)
                                                    if r == quadrant)
                                   for quadrant in range(4)))
            if previous is not None:
                pair_diffs.append(statistics.mean(abs(a - b)
                                                  for a, b in zip(pixels, previous)))
            previous = pixels

    print(f"frames={len(means)} bytes/frame={FRAME_BYTES} samples/frame={len(positions)}")
    print(f"frame_mean min={min(means):.2f} max={max(means):.2f} "
          f"mean={statistics.mean(means):.2f} std={statistics.pstdev(means):.2f}")
    print(f"adjacent_pixel_MAD mean={statistics.mean(pair_diffs):.2f} "
          f"max={max(pair_diffs):.2f} at pair={pair_diffs.index(max(pair_diffs))}/"
          f"{pair_diffs.index(max(pair_diffs)) + 1}")
    for parity in (0, 1):
        values = means[parity::2]
        print(f"frame_mean parity={parity}: {statistics.mean(values):.2f}")
    print("first_36_frame_means:", " ".join(f"{value:.1f}" for value in means[:36]))
    for quadrant in range(4):
        series = [row[quadrant] for row in quadrants]
        print(f"quadrant_{quadrant} min={min(series):.2f} max={max(series):.2f} "
              f"std={statistics.pstdev(series):.2f}; first_18=" +
              " ".join(f"{value:.1f}" for value in series[:18]))
    centered = [value - statistics.mean(means) for value in means]
    for lag in range(1, 7):
        top = sum(a * b for a, b in zip(centered[:-lag], centered[lag:]))
        bottom = sum(a * a for a in centered)
        print(f"mean_autocorr_lag_{lag}={top / bottom if bottom else 0:.3f}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Replay saved camera previews through candidate frame-delayed HE mappings.

This is an offline design probe. The source previews are 640x360 mode-0 gray
frames, so its numbers are directional and are not a board-level acceptance
test for the 1920x1080 Gaussian-plus-HE path.
"""

from __future__ import annotations

import json
from pathlib import Path
import zlib

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
CAPTURE = ROOT / "captures" / "preproc_recapture_20261003"


def frame(index: int) -> np.ndarray:
    pixels = zlib.decompress((CAPTURE / f"before_{index}.zlib").read_bytes())
    return np.frombuffer(pixels, dtype=np.uint8).reshape(360, 640)


def gaussian(image: np.ndarray) -> np.ndarray:
    p = np.pad(image.astype(np.uint16), 1, mode="edge")
    weighted = (
        p[:-2, :-2] + 2 * p[:-2, 1:-1] + p[:-2, 2:]
        + 2 * p[1:-1, :-2] + 4 * p[1:-1, 1:-1] + 2 * p[1:-1, 2:]
        + p[2:, :-2] + 2 * p[2:, 1:-1] + p[2:, 2:] + 8
    )
    return (weighted >> 4).astype(np.uint8)


def cdf_min_lut(image: np.ndarray) -> np.ndarray:
    counts = np.bincount(image.ravel(), minlength=256)
    cdf = np.cumsum(counts)
    first = cdf[np.flatnonzero(counts)[0]]
    if first == image.size:
        return np.arange(256, dtype=np.uint8)
    result = np.floor_divide(np.maximum(cdf - first, 0) * 255,
                             image.size - first)
    return result.clip(0, 255).astype(np.uint8)


def smooth(old: np.ndarray, raw: np.ndarray, shift: int) -> np.ndarray:
    if shift == 0:
        return raw
    old16 = old.astype(np.int16)
    diff = raw.astype(np.int16) - old16
    step = (np.abs(diff) + (1 << (shift - 1))) >> shift
    return (old16 + np.sign(diff) * step).clip(0, 255).astype(np.uint8)


def metrics(images: list[np.ndarray]) -> dict[str, float | list[float]]:
    stable = images[6:]
    means = np.array([image.mean() for image in stable])
    jumps = np.abs(np.diff(means))
    edges = [0.5 * (np.abs(np.diff(image.astype(np.int16), axis=1)).mean()
                    + np.abs(np.diff(image.astype(np.int16), axis=0)).mean())
             for image in stable]
    spans = [np.percentile(image, 95) - np.percentile(image, 5)
             for image in stable]
    return {"mean_jump": round(float(jumps.mean()), 3),
            "max_mean_jump": round(float(jumps.max()), 3),
            "p05_p95_span": round(float(np.mean(spans)), 3),
            "neighbor_gradient": round(float(np.mean(edges)), 3),
            "means": [round(float(v), 2) for v in means[:6]]}


def main() -> None:
    source = [gaussian(frame(i)) for i in range(3)]
    # Consecutive previews 0/1/2 are bright/dark/bright. Repeat the two
    # stable illumination phases to compare algorithms with one changed input.
    sequence = [source[i % 2] for i in range(24)]
    variants: dict[str, list[np.ndarray]] = {name: [] for name in
        ("gaussian_only", "he_delayed", "he_iir_1_2", "he_iir_1_4",
         "he_iir_1_8", "he_50pct", "he_iir_1_4_50pct")}
    for shift, name, blend in ((0, "he_delayed", 256),
                               (1, "he_iir_1_2", 256),
                               (2, "he_iir_1_4", 256),
                               (3, "he_iir_1_8", 256),
                               (0, "he_50pct", 128),
                               (2, "he_iir_1_4_50pct", 128)):
        lut = np.arange(256, dtype=np.uint8)
        for image in sequence:
            equalized = lut[image]
            output = ((image.astype(np.uint16) * (256 - blend)
                       + equalized.astype(np.uint16) * blend + 128) >> 8)
            variants[name].append(output.astype(np.uint8))
            lut = smooth(lut, cdf_min_lut(image), shift)
    variants["gaussian_only"] = sequence
    result = {name: metrics(images) for name, images in variants.items()}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

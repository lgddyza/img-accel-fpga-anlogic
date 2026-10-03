#!/usr/bin/env python3
"""Render downloaded GREY8 previews and summarize preprocessing effects."""

from __future__ import annotations

import json
from pathlib import Path
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFont


WIDTH = 640
HEIGHT = 360
FRAME_COUNT = 3
ROOT = Path(__file__).resolve().parents[1]
INPUT_DIR = ROOT / "captures" / "comparison_20261003"
FONT_PATH = Path("C:/Windows/Fonts/arial.ttf")


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    if FONT_PATH.exists():
        return ImageFont.truetype(str(FONT_PATH), size)
    return ImageFont.load_default()


def load_frame(kind: str, index: int) -> np.ndarray:
    payload = zlib.decompress((INPUT_DIR / f"{kind}_{index}.zlib").read_bytes())
    expected = WIDTH * HEIGHT
    if len(payload) != expected:
        raise ValueError(f"{kind}_{index}: expected {expected} bytes, got {len(payload)}")
    return np.frombuffer(payload, dtype=np.uint8).reshape(HEIGHT, WIDTH)


def metrics(frame: np.ndarray) -> dict[str, float]:
    values = frame.astype(np.float32)
    histogram = np.bincount(frame.ravel(), minlength=256).astype(np.float64)
    probability = histogram[histogram > 0] / frame.size
    edge_x = np.abs(np.diff(values, axis=1)).mean()
    edge_y = np.abs(np.diff(values, axis=0)).mean()
    percentiles = np.percentile(values, [1, 5, 50, 95, 99])
    return {
        "mean": float(values.mean()),
        "stddev": float(values.std()),
        "p01": float(percentiles[0]),
        "p05": float(percentiles[1]),
        "p50": float(percentiles[2]),
        "p95": float(percentiles[3]),
        "p99": float(percentiles[4]),
        "dynamic_p05_p95": float(percentiles[3] - percentiles[1]),
        "entropy_bits": float(-(probability * np.log2(probability)).sum()),
        "edge_mean": float((edge_x + edge_y) / 2.0),
        "black_pct": float((frame == 0).mean() * 100.0),
        "white_pct": float((frame == 255).mean() * 100.0),
    }


def draw_histogram(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                   before: np.ndarray, after: np.ndarray) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=(25, 28, 32), outline=(80, 86, 94), width=1)
    histograms = []
    for frame in (before, after):
        hist = np.bincount(frame.ravel(), minlength=256).astype(np.float64)
        histograms.append(np.log1p(hist))
    peak = max(float(hist.max()) for hist in histograms)
    colors = ((54, 190, 205), (244, 142, 67))
    for hist, color in zip(histograms, colors):
        points = []
        for level, count in enumerate(hist):
            x = x0 + 8 + level * (x1 - x0 - 16) / 255.0
            y = y1 - 18 - count * (y1 - y0 - 34) / peak
            points.append((x, y))
        draw.line(points, fill=color, width=2)
    draw.text((x0 + 8, y0 + 7), "log histogram", fill=(220, 223, 228), font=font(15))
    draw.text((x0 + 8, y1 - 17), "before", fill=colors[0], font=font(13))
    draw.text((x0 + 78, y1 - 17), "after", fill=colors[1], font=font(13))


def main() -> None:
    before = [load_frame("before", i) for i in range(FRAME_COUNT)]
    after = [load_frame("after", i) for i in range(FRAME_COUNT)]
    stats = {
        "capture": {
            "preview_resolution": [WIDTH, HEIGHT],
            "source_resolution": [1920, 1080],
            "sampling": "every third source pixel in x and y",
            "before_mode": "mode 0: grayscale only",
            "after_mode": "mode 3: Gaussian plus histogram equalization",
        },
        "frames": [],
    }

    for index, (raw, processed) in enumerate(zip(before, after), start=1):
        before_metrics = metrics(raw)
        after_metrics = metrics(processed)
        stats["frames"].append({
            "frame": index,
            "before": before_metrics,
            "after": after_metrics,
        })
        Image.fromarray(raw, mode="L").save(INPUT_DIR / f"before_{index}.png")
        Image.fromarray(processed, mode="L").save(INPUT_DIR / f"after_{index}.png")

    metric_names = ("stddev", "dynamic_p05_p95", "entropy_bits", "edge_mean",
                    "black_pct", "white_pct")
    stats["average"] = {}
    for kind in ("before", "after"):
        stats["average"][kind] = {
            name: float(np.mean([row[kind][name] for row in stats["frames"]]))
            for name in metric_names
        }

    margin = 18
    header = 58
    row_gap = 16
    hist_width = 300
    canvas_width = margin * 4 + WIDTH * 2 + hist_width
    canvas_height = header + margin + FRAME_COUNT * HEIGHT + (FRAME_COUNT - 1) * row_gap + margin
    canvas = Image.new("RGB", (canvas_width, canvas_height), (238, 240, 243))
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 14), "Before: grayscale only", fill=(25, 35, 42), font=font(26))
    draw.text((margin * 2 + WIDTH, 14), "After: Gaussian + histogram equalization",
              fill=(25, 35, 42), font=font(26))

    for index, (raw, processed) in enumerate(zip(before, after), start=1):
        y = header + margin + (index - 1) * (HEIGHT + row_gap)
        x_before = margin
        x_after = margin * 2 + WIDTH
        x_hist = margin * 3 + WIDTH * 2
        canvas.paste(Image.fromarray(raw, mode="L").convert("RGB"), (x_before, y))
        canvas.paste(Image.fromarray(processed, mode="L").convert("RGB"), (x_after, y))
        draw.rectangle((x_before, y, x_before + 112, y + 30), fill=(0, 0, 0))
        draw.text((x_before + 8, y + 5), f"Sequence {index}", fill="white", font=font(17))
        bm = stats["frames"][index - 1]["before"]
        am = stats["frames"][index - 1]["after"]
        draw.rectangle((x_after, y, x_after + 245, y + 30), fill=(0, 0, 0))
        draw.text((x_after + 8, y + 5),
                  f"mean {bm['mean']:.1f} -> {am['mean']:.1f}",
                  fill="white", font=font(17))
        draw_histogram(draw, (x_hist, y, x_hist + hist_width, y + HEIGHT), raw, processed)

    comparison_path = INPUT_DIR / "before_after_comparison.png"
    canvas.save(comparison_path, quality=95)
    (INPUT_DIR / "comparison_stats.json").write_text(
        json.dumps(stats, indent=2, ensure_ascii=True) + "\n", encoding="utf-8"
    )
    print(comparison_path)
    print(json.dumps(stats["average"], indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Render matched RK temporal-filter frames and a 20-frame luminance trace."""

from __future__ import annotations

import json
from pathlib import Path
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "captures" / "rk_temporal_comparison_20261003"
PREVIEWS = OUT / "continuous"
WIDTH, HEIGHT = 640, 360
MEANS = {
    "before": [138.170, 108.463, 137.979, 108.498, 138.192, 108.646,
               138.257, 108.632, 138.034, 108.496, 138.101, 108.456,
               138.110, 108.463, 138.070, 108.467, 137.945, 108.359,
               137.973, 108.412],
    "after": [138.170, 136.924, 136.909, 136.445, 136.508, 135.206,
              135.943, 135.264, 134.828, 134.345, 134.009, 133.626,
              133.273, 132.409, 133.098, 131.803, 132.567, 131.374,
              131.355, 131.392],
}


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    face = Path("C:/Windows/Fonts/arial.ttf")
    return ImageFont.truetype(str(face), size) if face.exists() else ImageFont.load_default()


def load(kind: str, index: int) -> np.ndarray:
    data = zlib.decompress((PREVIEWS / f"{kind}_{index}.zlib").read_bytes())
    if len(data) != WIDTH * HEIGHT:
        raise ValueError(f"Unexpected {kind}_{index} preview size: {len(data)}")
    return np.frombuffer(data, dtype=np.uint8).reshape(HEIGHT, WIDTH)


def frame_metrics(image: np.ndarray) -> dict[str, float]:
    gray = image.astype(np.float32)
    p05, p95 = np.percentile(image, [5, 95])
    return {
        "mean": round(float(gray.mean()), 3),
        "stddev": round(float(gray.std()), 3),
        "p05": round(float(p05), 3),
        "p95": round(float(p95), 3),
        "p05_p95_span": round(float(p95 - p05), 3),
        "edge_mean": round(float((np.abs(np.diff(gray, axis=0)).mean()
                                  + np.abs(np.diff(gray, axis=1)).mean()) / 2), 3),
        "black_pct": round(float((image == 0).mean() * 100), 3),
        "white_pct": round(float((image == 255).mean() * 100), 3),
    }


def draw_histogram(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                   before: np.ndarray, after: np.ndarray) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=(25, 28, 32), outline=(80, 86, 94), width=1)
    histograms = []
    for frame in (before, after):
        counts = np.bincount(frame.ravel(), minlength=256).astype(np.float64)
        histograms.append(np.log1p(counts))
    peak = max(float(counts.max()) for counts in histograms)
    colors = ((54, 190, 205), (244, 142, 67))
    for counts, color in zip(histograms, colors):
        points = []
        for level, count in enumerate(counts):
            x = x0 + 8 + level * (x1 - x0 - 16) / 255.0
            y = y1 - 18 - count * (y1 - y0 - 34) / peak
            points.append((x, y))
        draw.line(points, fill=color, width=2)
    draw.text((x0 + 8, y0 + 7), "log histogram", fill=(220, 223, 228), font=font(15))
    draw.text((x0 + 8, y1 - 17), "before", fill=colors[0], font=font(13))
    draw.text((x0 + 78, y1 - 17), "after", fill=colors[1], font=font(13))


def draw_comparison(before: list[np.ndarray], after: list[np.ndarray]) -> None:
    # Match the layout of the earlier grayscale-versus-HE comparison figure:
    # three image pairs, one histogram per pair, and identical dimensions.
    rows = 3
    margin, header, row_gap, histogram_width = 18, 58, 16, 300
    canvas = Image.new(
        "RGB",
        (margin * 4 + WIDTH * 2 + histogram_width,
         header + margin + rows * HEIGHT + (rows - 1) * row_gap + margin),
        (238, 240, 243),
    )
    draw = ImageDraw.Draw(canvas)
    draw.text((margin, 14), "Before: FPGA Gaussian + histogram equalization",
              fill=(25, 35, 42), font=font(23))
    draw.text((margin * 2 + WIDTH, 14), "After: RK temporal stabilization",
              fill=(25, 35, 42), font=font(26))

    for index in range(rows):
        y = header + margin + index * (HEIGHT + row_gap)
        x_before = margin
        x_after = margin * 2 + WIDTH
        x_hist = margin * 3 + WIDTH * 2
        raw, processed = before[index], after[index]
        canvas.paste(Image.fromarray(raw, mode="L").convert("RGB"), (x_before, y))
        canvas.paste(Image.fromarray(processed, mode="L").convert("RGB"), (x_after, y))
        draw.rectangle((x_before, y, x_before + 112, y + 30), fill=(0, 0, 0))
        draw.text((x_before + 8, y + 5), f"Sequence {index + 1}",
                  fill="white", font=font(17))
        draw.rectangle((x_after, y, x_after + 245, y + 30), fill=(0, 0, 0))
        draw.text((x_after + 8, y + 5),
                  f"mean {raw.mean():.1f} -> {processed.mean():.1f}",
                  fill="white", font=font(17))
        draw_histogram(draw, (x_hist, y, x_hist + histogram_width, y + HEIGHT),
                       raw, processed)
    canvas.save(OUT / "before_after_comparison.png")


def draw_trace() -> None:
    canvas = Image.new("RGB", (1080, 540), "#fbfcfd")
    draw = ImageDraw.Draw(canvas)
    draw.text((65, 16), "20 consecutive frames: sampled full-frame mean intensity",
              fill="#1f3447", font=font(27))
    x0, x1, y0, y1 = 75, 1020, 75, 440
    low, high = 100.0, 145.0
    for level in (100, 110, 120, 130, 140):
        y = y1 - (level - low) / (high - low) * (y1 - y0)
        draw.line((x0, y, x1, y), fill="#d7dee5", width=1)
        draw.text((26, y - 10), str(level), fill="#52616f", font=font(17))
    draw.line((x0, y0, x0, y1), fill="#607080", width=2)
    draw.line((x0, y1, x1, y1), fill="#607080", width=2)
    for i in range(20):
        x = x0 + i * (x1 - x0) / 19
        if i % 2 == 0 or i == 19:
            draw.text((x - 7, y1 + 10), str(i + 1), fill="#52616f", font=font(14))
    for kind, color in (("before", "#20849e"), ("after", "#df7841")):
        values = MEANS[kind]
        points = [(x0 + i * (x1 - x0) / 19,
                   y1 - (value - low) / (high - low) * (y1 - y0))
                  for i, value in enumerate(values)]
        draw.line(points, fill=color, width=3)
        for x, y in points:
            draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=color)
    draw.line((600, 480, 640, 480), fill="#20849e", width=4)
    draw.text((650, 469), "Before", fill="#1f3447", font=font(19))
    draw.line((760, 480, 800, 480), fill="#df7841", width=4)
    draw.text((810, 469), "After", fill="#1f3447", font=font(19))
    canvas.save(OUT / "mean_intensity_20_frames.png")


def main() -> None:
    before = [load("before", i) for i in range(8)]
    after = [load("after", i) for i in range(8)]
    records = []
    for i, (raw, processed) in enumerate(zip(before, after)):
        records.append({
            "source_frame_index_zero_based": i + 8,
            "before": frame_metrics(raw),
            "after": frame_metrics(processed),
            "same_frame_correlation": round(float(np.corrcoef(raw.ravel(), processed.ravel())[0, 1]), 6),
        })
    jumps = {kind: float(np.abs(np.diff(values[4:])).mean()) for kind, values in MEANS.items()}
    summary = {
        "source": "RK V4L2 20 consecutive 1920x1080 GREY8 frames in FPGA mode 3",
        "processing": "same on-board GStreamer rktemporalgray plugin, offline replay at 60/1",
        "full_frame_mean_sampling": "one fixed pixel out of every 64; frames 5-20 for jump metric",
        "preview": "source frames 9-16, every third pixel horizontally and vertically",
        "full20_sampled_means": MEANS,
        "adjacent_mean_jump_frames_5_20": {kind: round(jump, 3) for kind, jump in jumps.items()},
        "jump_reduction_percent": round((1 - jumps["after"] / jumps["before"]) * 100, 2),
        "preview_frames": records,
        "preview_mean_p05_p95_span": {
            kind: round(float(np.mean([record[kind]["p05_p95_span"] for record in records])), 3)
            for kind in ("before", "after")
        },
        "preview_mean_edge": {
            kind: round(float(np.mean([record[kind]["edge_mean"] for record in records])), 3)
            for kind in ("before", "after")
        },
    }
    (OUT / "comparison_stats.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    draw_comparison(before, after)
    draw_trace()
    print(json.dumps({key: summary[key] for key in (
        "adjacent_mean_jump_frames_5_20", "jump_reduction_percent",
        "preview_mean_p05_p95_span", "preview_mean_edge")}, indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Estimate still-JPEG byte rates on local UAV road images; not an FPGA benchmark."""

from __future__ import annotations

from io import BytesIO
import json
from pathlib import Path
import random

import numpy as np
from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
DATASET = Path(
    "E:/FPGA/测试图片数据/as585/无人机损伤/无人机视角的道路损害数据集/"
    "C3 无人机视角的道路损害数据集/UAV-roaddamage/JPEGImages"
)
OUTPUT = ROOT / "captures" / "road_jpeg_probe_20261003.json"
WIDTH, HEIGHT = 1920, 1080
QUALITIES = (75, 85, 95)


def main() -> None:
    files = sorted(DATASET.glob("*.jpg"))
    if len(files) < 20:
        raise RuntimeError(f"Need at least 20 road images; found {len(files)}")
    chosen = random.Random(20261003).sample(files, 20)
    rows = []
    for path in chosen:
        with Image.open(path) as source:
            gray = ImageOps.fit(source.convert("L"), (WIDTH, HEIGHT), Image.Resampling.LANCZOS)
        original = np.asarray(gray, dtype=np.int16)
        samples = {}
        for quality in QUALITIES:
            encoded = BytesIO()
            gray.save(encoded, format="JPEG", quality=quality, optimize=False)
            payload = encoded.getvalue()
            with Image.open(BytesIO(payload)) as decoded:
                restored = np.asarray(decoded.convert("L"), dtype=np.int16)
            error = original - restored
            mse = float(np.mean(error.astype(np.float32) ** 2))
            samples[str(quality)] = {
                "bytes": len(payload),
                "ratio_vs_gray8": round(WIDTH * HEIGHT / len(payload), 3),
                "psnr_db": round(float(10 * np.log10(255 ** 2 / mse)), 3),
            }
        rows.append({"file": path.name, "jpeg": samples})
    report = {
        "meaning": "Software still-JPEG proxy; not synthesized FPGA resource, throughput, or crack-detection accuracy",
        "dataset": str(DATASET),
        "sample_count": len(rows),
        "resize": "grayscale center fit to 1920x1080, LANCZOS",
        "raw_gray8_bytes": WIDTH * HEIGHT,
        "quality_summary": {
            str(q): {
                "mean_bytes": round(float(np.mean([r["jpeg"][str(q)]["bytes"] for r in rows]))),
                "min_bytes": min(r["jpeg"][str(q)]["bytes"] for r in rows),
                "max_bytes": max(r["jpeg"][str(q)]["bytes"] for r in rows),
                "mean_ratio": round(float(np.mean([r["jpeg"][str(q)]["ratio_vs_gray8"] for r in rows])), 3),
                "mean_psnr_db": round(float(np.mean([r["jpeg"][str(q)]["psnr_db"] for r in rows])), 3),
            }
            for q in QUALITIES
        },
        "images": rows,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["quality_summary"], indent=2))
    print(OUTPUT)


if __name__ == "__main__":
    main()

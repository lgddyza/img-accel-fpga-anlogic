"""Decode real-encoder simulation artifacts and compare reconstructed frames."""
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/stream_fix"
results = []
for frame in range(4):
    pixels = np.zeros((48, 1920), dtype=np.uint8)
    sizes = []
    for tile in range(3):
        path = OUT / f"sim_frame_{frame}_tile_{tile}.jpg"
        raw = path.read_bytes()
        if not raw.startswith(b"\xff\xd8") or not raw.endswith(b"\xff\xd9"):
            raise SystemExit(f"Incomplete JPEG: {path}")
        with Image.open(path) as image:
            image.load()
            if image.size != (1920, 16) or image.mode != "L":
                raise SystemExit(f"Wrong JPEG geometry/format: {path}")
            decoded = np.array(image)
        for stripe in range(2):
            row = (stripe * 3 + tile) * 8
            pixels[row:row + 8] = decoded[stripe * 8:stripe * 8 + 8]
        sizes.append(len(raw))
    y, x = np.indices(pixels.shape, dtype=np.int64)
    hashed = ((x + 1) * 0x045d9f3b ^ (y + 13) * 0x119de1f3) & 0xffffffff
    hashed ^= hashed >> 16
    expected = 90 + frame * 30 + ((x // 64 + y // 64) % 6) * 5 + (hashed & 15)
    expected -= 48 * ((x % 317 == 53) | (x % 317 == 54) | ((x + y // 3) % 491 == 75))
    error = pixels.astype(np.float64) - expected
    mae = float(np.mean(np.abs(error)))
    psnr = float(10 * math.log10(255 ** 2 / np.mean(error ** 2)))
    if mae > 8 or psnr < 28:
        raise SystemExit(f"Frame order/content mismatch: frame={frame}, MAE={mae}, PSNR={psnr}")
    results.append(dict(frame=frame, tile_bytes=sizes, mae=round(mae, 4), psnr_db=round(psnr, 4)))
(OUT / "jpeg_validation.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
print(json.dumps(results, indent=2))
print("PASS 12 JPEGs decoded, four simulated full-width 1920x48 frames reconstructed and checked")

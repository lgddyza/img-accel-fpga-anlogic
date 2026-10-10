"""Decode six simulated JPEG packets and rebuild their 8-row stripe frames."""
import json
from pathlib import Path

import cv2
import numpy as np

DIRECTORY = Path(__file__).resolve().parent / "ehp2_sim/jpeg"


def blackhat_reference():
    yy, xx = np.indices((1080, 1920), dtype=np.uint32)
    hashed = (xx + 1) * np.uint32(0x045d9f3b) ^ (yy + 13) * np.uint32(0x119de1f3)
    hashed ^= hashed >> 16
    raw = (112 + ((xx // 64 + yy // 64) % 6) * 5 + (hashed & 15)).astype(np.int16)
    crack = (xx % 317 == 53) | (xx % 317 == 54) | ((xx + yy // 3) % 491 == 75)
    raw[crack] -= 48
    raw = raw.astype(np.uint8)
    response = cv2.morphologyEx(raw, cv2.MORPH_BLACKHAT, np.ones((3, 3), np.uint8),
                                borderType=cv2.BORDER_REPLICATE)
    kernels = (np.ones((1, 5), np.uint8), np.ones((5, 1), np.uint8),
               np.eye(5, dtype=np.uint8), np.fliplr(np.eye(5, dtype=np.uint8)))
    filtered = np.maximum.reduce([cv2.morphologyEx(response, cv2.MORPH_OPEN, kernel,
                                 borderType=cv2.BORDER_REPLICATE) for kernel in kernels])
    return np.clip(raw.astype(np.int16) - filtered, 0, 255).astype(np.uint8)


def main():
    frames = []
    for frame, mode in enumerate(("blackhat", "blackhat_clahe")):
        tiles = []
        packets = []
        for lane in range(3):
            path = DIRECTORY / f"frame_{frame}_tile_{lane}.jpg"
            payload = path.read_bytes()
            if not payload.startswith(b"\xff\xd8") or not payload.endswith(b"\xff\xd9"):
                raise RuntimeError(f"Invalid JPEG markers: {path}")
            decoded = cv2.imdecode(np.frombuffer(payload, dtype=np.uint8), cv2.IMREAD_GRAYSCALE)
            if decoded is None or decoded.shape != (360, 1920):
                raise RuntimeError(f"JPEG decode or dimensions failed: {path}")
            tiles.append(decoded)
            packets.append({"file": path.name, "bytes": len(payload),
                            "width": 1920, "height": 360})
        rebuilt = np.empty((1080, 1920), dtype=np.uint8)
        for stripe in range(135):
            lane = stripe % 3
            row = (stripe // 3) * 8
            rebuilt[stripe * 8:(stripe + 1) * 8] = tiles[lane][row:row + 8]
        if float(rebuilt.std()) < 1:
            raise RuntimeError(f"Blank or constant reconstructed frame: {mode}")
        output = DIRECTORY / f"reconstructed_{mode}.png"
        if not cv2.imwrite(str(output), rebuilt):
            raise RuntimeError(f"Failed to save {output}")
        frames.append({"mode": mode, "image": output.name,
                       "mean": float(rebuilt.mean()), "std": float(rebuilt.std()),
                       "min": int(rebuilt.min()), "max": int(rebuilt.max()),
                       "packets": packets})
        if frame == 0:
            difference = rebuilt.astype(np.int16) - blackhat_reference().astype(np.int16)
            frames[-1]["opencv_reference_mae"] = float(np.abs(difference).mean())
            frames[-1]["opencv_reference_psnr_db"] = float(
                10 * np.log10(255.0 ** 2 / max(float((difference.astype(np.float64) ** 2).mean()), 1e-12)))
            if frames[-1]["opencv_reference_mae"] > 8:
                raise RuntimeError("Decoded blackhat frame differs substantially from OpenCV reference")
    report = {"source": "RTL simulation of synthetic road texture, not camera capture",
              "frames": frames}
    (DIRECTORY / "decode_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    print("PASS six JPEG packets decoded, two 1920x1080 frames reconstructed")


if __name__ == "__main__":
    main()

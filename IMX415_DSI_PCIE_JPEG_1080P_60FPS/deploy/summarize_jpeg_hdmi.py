#!/usr/bin/env python3
"""Make a small before/after preview from near-time GREY and JPEG frames."""

from pathlib import Path
import statistics
import zlib

W, H = 1920, 1080
BASE = Path("/root/jpeg_rk")


def describe(name, frame):
    hist = [0] * 256
    for level in frame:
        hist[level] += 1
    total = len(frame)
    print(f"{name}: mean={sum(frame)/total:.2f} "
          f"black<16={sum(hist[:16])/total:.3%} "
          f"white>239={sum(hist[240:])/total:.3%}")
    return hist


def scale(frame):
    out = bytearray()
    for y in range(0, H, 4):
        out.extend(frame[y * W:(y + 1) * W:4])
    return out


def main():
    raw = (BASE / "raw_compare.gray").read_bytes()
    pgm = (BASE / "jpeg_hdmi_live/jpeg_hdmi_003.pgm").read_bytes()
    header = b"P5\n1920 1080\n255\n"
    if len(raw) != W * H or not pgm.startswith(header):
        raise ValueError("unexpected GREY or PGM format")
    jpeg = pgm[len(header):]
    if len(jpeg) != W * H:
        raise ValueError("incomplete JPEG reconstruction")
    describe("raw preprocessed PCIe", raw)
    describe("decoded JPEG", jpeg)
    seam = [[], [], []]
    inner = []
    for y in range(H - 1):
        a = jpeg[y * W:(y + 1) * W:32]
        b = jpeg[(y + 1) * W:(y + 2) * W:32]
        value = sum(abs(x - z) for x, z in zip(a, b)) / len(a)
        (seam[(y // 8) % 3] if y % 8 == 7 else inner).append(value)
    print("JPEG row differences: inner={:.2f} A/B={:.2f} B/C={:.2f} C/A={:.2f}".format(
        statistics.mean(inner), *(statistics.mean(part) for part in seam)))
    left, right = scale(raw), scale(jpeg)
    preview = bytearray()
    for y in range(H // 4):
        preview.extend(left[y * (W // 4):(y + 1) * (W // 4)])
        preview.extend(right[y * (W // 4):(y + 1) * (W // 4)])
    pgm_preview = b"P5\n960 270\n255\n" + preview
    output = BASE / "jpeg_hdmi_comparison.pgm.z"
    output.write_bytes(zlib.compress(pgm_preview, 9))
    print(f"preview={output} bytes={output.stat().st_size}")


if __name__ == "__main__":
    main()

"""Reconstruct real RK JPEG tile captures and summarize CLAHE board test."""

from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
WIDTH, HEIGHT = 1920, 1080


def load_frame(mode: str, frame: int) -> tuple[Image.Image, int]:
    stem = ROOT / mode / f"frame_{frame:05d}"
    strips = []
    total_bytes = 0
    for tile in "abc":
        path = stem.with_suffix(f".{tile}.jpg")
        total_bytes += path.stat().st_size
        with Image.open(path) as encoded:
            strips.append(np.asarray(encoded.convert("L")).copy())
    if any(item.shape != (360, WIDTH) for item in strips):
        raise ValueError("unexpected JPEG tile dimensions")
    out = np.empty((HEIGHT, WIDTH), dtype=np.uint8)
    for stripe in range(135):
        source = strips[stripe % 3]
        source_row = (stripe // 3) * 8
        out[stripe * 8:(stripe + 1) * 8] = source[source_row:source_row + 8]
    image = Image.fromarray(out, "L")
    image.save(stem.with_suffix(".png"))
    return image, total_bytes


def measure(image: Image.Image, total_bytes: int) -> dict:
    array = np.asarray(image, dtype=np.uint8)
    # A fixed central region reduces the influence of moving objects at edges.
    roi = array[270:810, 480:1440]
    hist = np.bincount(array.ravel(), minlength=256)
    values = {
        "jpeg_bytes": total_bytes,
        "mean": round(float(array.mean()), 2),
        "std": round(float(array.std()), 2),
        "p05": int(np.percentile(array, 5)),
        "p95": int(np.percentile(array, 95)),
        "roi_std": round(float(roi.std()), 2),
        "hist_nonzero_bins": int(np.count_nonzero(hist)),
        "clipped_white_percent": round(float(np.mean(array == 255) * 100), 3),
    }
    return values


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", size)


def draw_histogram(draw: ImageDraw.ImageDraw, before: Image.Image,
                   after: Image.Image, x: int, y: int) -> None:
    # Fixed bin count and common log scale make the two distributions comparable.
    first = np.bincount(np.asarray(before).ravel(), minlength=256).reshape(64, 4).sum(axis=1)
    second = np.bincount(np.asarray(after).ravel(), minlength=256).reshape(64, 4).sum(axis=1)
    left, top, width, height = x + 12, y + 88, 306, 305
    draw.rectangle((x, y, x + 330, y + 438), fill=(20, 25, 30))
    draw.text((x + 15, y + 15), "灰度直方图（对数）", font=font(22), fill="white")
    for index in range(64):
        a = np.log1p(first[index]) / np.log1p(first.max())
        b = np.log1p(second[index]) / np.log1p(second.max())
        xx = left + index * 4.7
        draw.line((xx, top + height, xx, top + height - a * height), fill=(42, 200, 213), width=2)
        draw.line((xx + 2, top + height, xx + 2, top + height - b * height), fill=(255, 152, 44), width=2)
    draw.text((x + 18, y + 405), "高斯", font=font(19), fill=(42, 200, 213))
    draw.text((x + 103, y + 405), "CLAHE", font=font(19), fill=(255, 152, 44))


def make_comparison(report: dict) -> None:
    canvas = Image.new("RGB", (1980, 1110), (241, 244, 248))
    draw = ImageDraw.Draw(canvas)
    draw.text((22, 10), "RK 实际 JPEG 解码画面对比：高斯基线 / 高斯＋CLAHE",
              font=font(36), fill=(25, 37, 49))
    draw.text((22, 61), "同机位依次拍摄，非同一时刻帧；1920×1080、JPEG QF 85、FPGA 60 FPS 模式",
              font=font(20), fill=(73, 89, 106))
    for row, frame in enumerate((2, 3)):
        y = 108 + row * 500
        draw.text((22, y), f"样本 {row + 1}", font=font(25), fill=(20, 30, 40))
        images = {}
        for col, (mode, title) in enumerate((("gauss", "仅高斯处理"), ("clahe", "高斯＋CLAHE"))):
            image = Image.open(ROOT / mode / f"frame_{frame:05d}.png").convert("L")
            images[mode] = image
            x = 22 + col * 800
            draw.text((x + 115, y), title, font=font(24), fill=(20, 30, 40))
            thumb = image.resize((780, 439), Image.Resampling.LANCZOS).convert("RGB")
            canvas.paste(thumb, (x, y + 40))
            item = report[mode][str(frame)]
            label = f"均值 {item['mean']:.1f}  |  局部标准差 {item['roi_std']:.1f}  |  JPEG {item['jpeg_bytes']/1024:.1f} KiB"
            draw.rectangle((x, y + 40, x + 780, y + 75), fill=(0, 0, 0))
            draw.text((x + 10, y + 42), label, font=font(19), fill="white")
        draw_histogram(draw, images["gauss"], images["clahe"], 1622, y + 40)
    canvas.save(ROOT / "comparison_gauss_clahe.png")

    # A separate lossless close-up preserves the detail lost in the full-frame thumbnail.
    crop = (590, 145, 1190, 695)
    close = Image.new("RGB", (1240, 1240), (241, 244, 248))
    close_draw = ImageDraw.Draw(close)
    close_draw.text((20, 12), "固定区域细节放大（百叶窗及暗部）", font=font(32), fill=(25, 37, 49))
    for row, frame in enumerate((2, 3)):
        for col, mode in enumerate(("gauss", "clahe")):
            source = Image.open(ROOT / mode / f"frame_{frame:05d}.png").convert("L")
            detail = source.crop(crop).resize((600, 550), Image.Resampling.NEAREST).convert("RGB")
            x, y = 20 + col * 620, 70 + row * 585
            close.paste(detail, (x, y))
            close_draw.rectangle((x, y, x + 600, y + 35), fill=(0, 0, 0))
            close_draw.text((x + 8, y + 1), f"样本 {row + 1}  {'高斯' if mode == 'gauss' else '高斯＋CLAHE'}",
                            font=font(20), fill="white")
    close.save(ROOT / "detail_gauss_clahe.png")


def main() -> None:
    report = {}
    for mode in ("gauss", "clahe"):
        report[mode] = {}
        for frame in (2, 3):
            image, size = load_frame(mode, frame)
            report[mode][str(frame)] = measure(image, size)
    (ROOT / "metrics.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    make_comparison(report)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

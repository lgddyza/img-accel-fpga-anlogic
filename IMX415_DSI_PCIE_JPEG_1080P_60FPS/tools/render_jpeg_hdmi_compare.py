"""Render the near-time board capture preview as a labeled PNG."""

from pathlib import Path
import zlib

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / "captures/jpeg_hdmi_comparison.pgm.z"
output = ROOT / "captures/jpeg_hdmi_compare.png"
raw = zlib.decompress(source.read_bytes())
header = b"P5\n960 270\n255\n"
if not raw.startswith(header) or len(raw) != len(header) + 960 * 270:
    raise ValueError("invalid preview")
pixels = Image.frombytes("L", (960, 270), raw[len(header):])
left = pixels.crop((0, 0, 480, 270)).resize((960, 540))
right = pixels.crop((480, 0, 960, 270)).resize((960, 540))
canvas = Image.new("RGB", (1940, 630), "#eef1f4")
canvas.paste(left.convert("RGB"), (10, 80))
canvas.paste(right.convert("RGB"), (970, 80))
draw = ImageDraw.Draw(canvas)
font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 28)
small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 19)
draw.text((18, 20), "Before: FPGA preprocessed GREY8", fill="#18232d", font=font)
draw.text((978, 20), "After: JPEG Q85 decoded on RK", fill="#18232d", font=font)
draw.text((18, 55), "Mean 149.11  |  near-time capture", fill="#263946", font=small)
draw.text((978, 55), "Mean 148.59  |  3 tiles interwoven", fill="#263946", font=small)
canvas.save(output)
print(output)

from pathlib import Path
import zlib
from PIL import Image, ImageStat, ImageChops, ImageOps

root = Path(__file__).resolve().parents[1] / "captures"
images = []
for index in range(3):
    pixels = zlib.decompress((root / f"frame_{index}.zlib").read_bytes())
    assert len(pixels) == 640 * 360, len(pixels)
    image = Image.frombytes("L", (640, 360), pixels)
    image.save(root / f"frame_{index}.png")
    stat = ImageStat.Stat(image)
    images.append(image)
    print(f"frame_{index}: min={image.getextrema()[0]} max={image.getextrema()[1]} mean={stat.mean[0]:.1f} stddev={stat.stddev[0]:.1f}")
for index in range(1, 3):
    diff = ImageChops.difference(images[index - 1], images[index])
    print(f"frame_{index-1}->{index}: mean absolute difference={ImageStat.Stat(diff).mean[0]:.2f}")

full = root / "full"
for index in range(3):
    pixels = zlib.decompress((full / f"frame_{index}.zlib").read_bytes())
    assert len(pixels) == 1920 * 1080, len(pixels)
    image = Image.frombytes("L", (1920, 1080), pixels)
    image.save(full / f"frame_{index}.png")
    ImageOps.autocontrast(image, cutoff=0.5).save(full / f"frame_{index}_enhanced.png")
    stat = ImageStat.Stat(image)
    print(f"full frame_{index}: min={image.getextrema()[0]} max={image.getextrema()[1]} mean={stat.mean[0]:.1f} stddev={stat.stddev[0]:.1f}")

hdmi = root / "hdmi"
if (hdmi / "frame_0.zlib").exists():
    pixels = zlib.decompress((hdmi / "frame_0.zlib").read_bytes())
    assert len(pixels) == 1920 * 1080, len(pixels)
    image = Image.frombytes("L", (1920, 1080), pixels)
    image.save(hdmi / "frame_0.png")
    print(f"HDMI display transform preview: min={image.getextrema()[0]} max={image.getextrema()[1]} mean={ImageStat.Stat(image).mean[0]:.1f}")

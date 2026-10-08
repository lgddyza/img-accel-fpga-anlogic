"""Decode the three strict DMA captures made after the DSI OSD bitstream."""

from pathlib import Path
import json
import zlib

from PIL import Image, ImageChops, ImageOps, ImageStat


root = Path(__file__).resolve().parents[1] / "captures" / "after_bit_20261001"
images = []
stats = []
for index in range(3):
    raw = zlib.decompress((root / f"frame_{index}_640x360.zlib").read_bytes())
    assert len(raw) == 640 * 360
    image = Image.frombytes("L", (640, 360), raw)
    image.save(root / f"frame_{index}.png")
    ImageOps.autocontrast(image, cutoff=0.5).save(root / f"frame_{index}_enhanced.png")
    images.append(image)
    stats.append({
        "frame": index,
        "min": image.getextrema()[0],
        "max": image.getextrema()[1],
        "mean": round(ImageStat.Stat(image).mean[0], 2),
    })

full = zlib.decompress((root / "frame_0_1920x1080.zlib").read_bytes())
assert len(full) == 1920 * 1080
Image.frombytes("L", (1920, 1080), full).save(root / "frame_0_1920x1080.png")

# These Y planes were read from the actual NV12 buffers handed to kmssink,
# after brightness/contrast, resolution text, and fpsdisplaysink text.
for index in range(3):
    raw = zlib.decompress((root / f"hdmi_sink_{index}_640x360.zlib").read_bytes())
    assert len(raw) == 640 * 360
    Image.frombytes("L", (640, 360), raw).save(root / f"hdmi_sink_{index}.png")
full_sink = zlib.decompress((root / "hdmi_sink_0_1920x1080.zlib").read_bytes())
assert len(full_sink) == 1920 * 1080
Image.frombytes("L", (1920, 1080), full_sink).save(
    root / "hdmi_sink_0_1920x1080.png"
)

for index in (1, 2):
    diff = ImageChops.difference(images[index - 1], images[index])
    stats[index]["mean_abs_diff_from_previous"] = round(ImageStat.Stat(diff).mean[0], 2)

(root / "capture_stats.json").write_text(
    json.dumps(stats, indent=2) + "\n", encoding="utf-8"
)
print(json.dumps(stats, indent=2))

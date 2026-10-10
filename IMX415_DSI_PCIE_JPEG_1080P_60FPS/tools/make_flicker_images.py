from pathlib import Path
import zlib
from PIL import Image, ImageOps, ImageChops, ImageStat

root = Path(__file__).resolve().parents[1] / "captures" / "flicker"
for index in (0, 1, 10, 11, 14, 15):
    pixels = zlib.decompress((root / f"frame_{index}.zlib").read_bytes())
    assert len(pixels) == 640 * 360
    image = Image.frombytes("L", (640, 360), pixels)
    image.save(root / f"frame_{index}.png")
    print(index, image.getextrema(), round(ImageStat.Stat(image).mean[0], 3))
for a, b in ((0, 1), (10, 11), (14, 15)):
    ia = Image.open(root / f"frame_{a}.png")
    ib = Image.open(root / f"frame_{b}.png")
    diff = ImageChops.difference(ia, ib)
    ImageOps.autocontrast(diff, cutoff=0).save(root / f"diff_{a}_{b}.png")
    print(f"{a}->{b}: diff mean={ImageStat.Stat(diff).mean[0]:.3f}")

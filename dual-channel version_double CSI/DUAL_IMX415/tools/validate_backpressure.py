"""Check reconstructed noisy frames after long pauses through real RTL JPEG."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[1]
out = root / 'build/str2_backpressure'
rng = 0x84937251
report = []
for frame in range(2):
    expected = np.empty((96, 1920), dtype=np.uint8)
    for i in range(expected.size):
        rng = (rng ^ (rng << 13)) & 0xffffffff
        rng ^= rng >> 17
        rng = (rng ^ (rng << 5)) & 0xffffffff
        expected.flat[i] = rng & 255
    reconstructed = np.empty_like(expected)
    sizes = []
    for tile in range(3):
        path = out / f'frame_{frame}_tile_{tile}.jpg'
        sizes.append(path.stat().st_size)
        with Image.open(path) as image:
            image.load()
            assert image.size == (1920, 32) and image.mode == 'L'
            rows = np.array(image)
        for stripe in range(4):
            y = (stripe*3+tile)*8
            reconstructed[y:y+8] = rows[stripe*8:stripe*8+8]
    error = reconstructed.astype(np.float64)-expected
    mae = float(np.abs(error).mean())
    psnr = float(10*np.log10(255**2/np.square(error).mean()))
    assert min(sizes) > 16384 and mae < 12 and psnr > 24, (frame, sizes, mae, psnr)
    report.append(dict(frame=frame, jpeg_bytes=sizes, mae=mae, psnr_db=psnr))
(out / 'validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
print('PASS six large JPEGs decode and reconstruct the exact input ordering')

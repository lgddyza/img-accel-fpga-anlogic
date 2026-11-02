"""Decode real RTL JPEG stripes and compare with the actual pre-encoder pixels."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
parser.add_argument('--frames', type=int, default=2)
parser.add_argument('--minimum-psnr', type=float, default=32)
args = parser.parse_args()
results = []
for frame in range(args.frames):
    reference = np.asarray(Image.open(args.directory/f'expected_{frame}.pgm'))
    if reference.shape != (1080, 1920):
        raise SystemExit('Incomplete or incorrect reference image')
    decoded = np.empty_like(reference)
    hashes = []
    for lane in range(3):
        path = args.directory/f'cam_{frame}_tile_{lane}.jpg'
        payload = path.read_bytes()
        if payload[:2] != b'\xff\xd8' or payload[-2:] != b'\xff\xd9':
            raise SystemExit(f'Incomplete JPEG: {path}')
        with Image.open(path) as image:
            image.load()
            tile = np.asarray(image.convert('L'))
        if tile.shape != (360, 1920):
            raise SystemExit(f'Incorrect JPEG dimensions: {path}')
        for stripe in range(45):
            y = stripe*24 + lane*8
            decoded[y:y+8] = tile[stripe*8:stripe*8+8]
        hashes.append(hashlib.sha256(payload).hexdigest())
    difference = reference.astype(np.float64)-decoded.astype(np.float64)
    mse = float(np.mean(difference**2))
    psnr = float(10*np.log10(255**2/mse)) if mse else 999.0
    results.append(dict(frame=frame, psnr_db=psnr,
                        mae=float(np.mean(np.abs(difference))),
                        worst_row_mae=float(np.abs(difference).mean(axis=1).max()),
                        jpeg_sha256=hashes))
    Image.fromarray(reference).save(args.directory/f'input_{frame}.png')
    Image.fromarray(decoded).save(args.directory/f'decoded_{frame}.png')
    Image.fromarray(np.clip(np.abs(difference)*8, 0, 255).astype(np.uint8)).save(
        args.directory/f'difference_x8_{frame}.png')
(args.directory/'image_checks.json').write_text(json.dumps(results, indent=2)+'\n',
                                               encoding='utf-8')
print(json.dumps(results, indent=2))
if any(result['psnr_db'] < args.minimum_psnr for result in results):
    raise SystemExit('Image comparison failed: investigate corruption or JPEG quality')
print('PASS decoded geometry, stripe weave and reference image comparison')

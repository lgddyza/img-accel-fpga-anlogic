"""Validate every emitted DQT entry and decode all simulated JPEG stripes."""
from pathlib import Path
import argparse
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--directory',type=Path,default=ROOT/'build')
parser.add_argument('--width',type=int,default=64)
parser.add_argument('--height',type=int,default=8,help='height of each JPEG tile')
parser.add_argument('--frames',type=int,default=5,choices=range(1,6))
args = parser.parse_args()
BASE = [16,11,10,16,24,40,51,61,12,12,14,19,26,58,60,55,
        14,13,16,24,40,57,69,56,14,17,22,29,51,87,80,62,
        18,22,37,56,68,109,103,77,24,35,55,64,81,104,113,92,
        49,64,78,87,103,121,120,101,72,92,95,98,112,100,103,99]
for frame, quality in enumerate((85, 30, 95, 1, 65)[:args.frames]):
    scale = 200 - 2 * quality if quality >= 50 else 5000 // quality
    expected = [max(1, min(255, ((value * scale + 50) * 1311) >> 17)) for value in BASE]
    for tile in range(3):
        path = args.directory / f'cam_{frame}_tile_{tile}.jpg'
        with Image.open(path) as image:
            image.load()
            assert image.size == (args.width, args.height), path
            assert image.quantization[0] == expected, (path, image.quantization[0], expected)
    print(f'PASS frame={frame} QF={quality}: three decoded JPEGs, all 64 DQT entries')

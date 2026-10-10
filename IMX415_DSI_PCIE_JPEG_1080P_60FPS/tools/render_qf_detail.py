#!/usr/bin/env python3
"""Magnify actual decoded FPGA JPEG samples without adding image detail."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

CAPTURE = (Path(__file__).resolve().parents[1] / 'captures' /
           'qf_sweep_20261007')
FONT = 'C:/Windows/Fonts/msyh.ttc'
QFS = (30, 50, 70, 90)
CROP = (825, 435, 1145, 675)


def main():
    canvas = Image.new('RGB', (1360, 1235), '#f3f5f8')
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(FONT, 33)
    label_font = ImageFont.truetype(FONT, 23)
    draw.text((35, 20), '实际 FPGA JPEG 局部像素放大：相同场景，不同采集时刻',
              font=title_font, fill='#15212f')
    draw.text((35, 68), '每个源像素放大 2×，无插值、锐化或 RK 去闪处理；亮度相位已尽量匹配',
              font=label_font, fill='#526173')
    for index, qf in enumerate(QFS):
        with Image.open(CAPTURE / f'qf{qf}_reconstructed.png') as source:
            crop = source.crop(CROP)
        pixels = np.asarray(crop, dtype=np.int16)
        edge = (np.abs(np.diff(pixels, axis=0)).mean() +
                np.abs(np.diff(pixels, axis=1)).mean()) / 2
        qtable = Image.open(CAPTURE / f'qf{qf}_a.jpg').quantization[0]
        x = 25 + (index % 2) * 670
        y = 118 + (index // 2) * 550
        draw.rounded_rectangle((x, y, x + 650, y + 535), radius=10,
                               fill='white')
        draw.text((x + 12, y + 8), f'QF {qf}    JPEG 量化表首项={qtable[0]}',
                  font=label_font, fill='#15212f')
        enlarged = crop.resize((640, 480), Image.Resampling.NEAREST)
        canvas.paste(enlarged.convert('RGB'), (x + 5, y + 43))
        print(f'QF{qf} ROI mean={pixels.mean():.3f} edge={edge:.3f} '
              f'qtable_dc={qtable[0]}')
    output = CAPTURE / 'pixel_detail_comparison.png'
    canvas.save(output)
    print(output)


if __name__ == '__main__':
    main()

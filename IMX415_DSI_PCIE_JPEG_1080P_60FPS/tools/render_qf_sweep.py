#!/usr/bin/env python3
"""Render an RK QF sweep: chart and actual three-tile JPEG camera samples."""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
CAPTURE = ROOT / 'captures' / 'qf_sweep_20261007'
FONT_PATH = Path('C:/Windows/Fonts/msyh.ttc')


def font(size):
    return ImageFont.truetype(str(FONT_PATH), size) if FONT_PATH.exists() else ImageFont.load_default()


def restore(quality):
    tiles = []
    for tile in 'abc':
        with Image.open(CAPTURE / f'qf{quality}_{tile}.jpg') as image:
            if image.size != (1920, 360):
                raise ValueError(f'QF{quality} tile {tile}: {image.size}')
            tiles.append(np.asarray(image.convert('L')))
    full = np.empty((1080, 1920), dtype=np.uint8)
    for stripe in range(135):
        source = tiles[stripe % 3]
        start = (stripe // 3) * 8
        full[stripe * 8:(stripe + 1) * 8] = source[start:start + 8]
    return Image.fromarray(full, mode='L')


def chart(results):
    width, height = 1500, 650
    im = Image.new('RGB', (width, height), '#f3f5f8')
    draw = ImageDraw.Draw(im)
    f_title, f_axis, f_label = font(40), font(25), font(23)
    draw.text((65, 28), 'FPGA JPEG 质量参数实测：PCIe 视频载荷', fill='#15212f', font=f_title)
    draw.text((67, 88), '1920×1080 灰度 / 三路 JPEG / 每档 180 帧 / 60 FPS',
              fill='#46566b', font=f_label)
    left, right, top, bottom = 120, 1400, 155, 530
    scale_max = max(350, ((max(item['mean_bytes'] for item in results) / 1000 + 49) // 50) * 50)
    for tick in range(0, int(scale_max) + 1, 50):
        y = bottom - tick / scale_max * (bottom - top)
        draw.line((left, y, right, y), fill='#dce3ea', width=2)
        draw.text((65, y - 14), str(tick), fill='#526173', font=f_axis)
    draw.text((116, 120), 'KB / 帧', fill='#526173', font=f_axis)
    colors = ['#738eae', '#668caf', '#518cb6', '#398cb8', '#288bad', '#137f9c', '#e46d39']
    for i, item in enumerate(results):
        center = left + 100 + i * 177
        kb = item['mean_bytes'] / 1000
        y = bottom - kb / scale_max * (bottom - top)
        draw.rounded_rectangle((center - 52, y, center + 52, bottom), radius=8,
                               fill=colors[i])
        draw.text((center - 45, y - 35), f'{kb:.1f}', fill='#15212f', font=f_axis)
        draw.text((center - 43, bottom + 14), f'QF{item["qf"]}',
                  fill='#15212f', font=f_axis)
        draw.text((center - 55, bottom + 52), f'{item["mbps_at_60fps"]:.1f} Mb/s',
                  fill='#526173', font=f_label)
    draw.text((65, 605), '码率不含 PCIe、DMA 和协议开销。各档于不同时刻采集，场景与光照可能变化。',
              fill='#526173', font=font(19))
    out = CAPTURE / 'bitrate_comparison.png'
    im.save(out)
    print(out)


def visual(results, frames, crop):
    cw, ch = 560, 315
    width = 1500
    row_height = 330
    header = 95
    im = Image.new('RGB', (width, header + row_height * len(results) + 25), '#f3f5f8')
    draw = ImageDraw.Draw(im)
    draw.text((28, 17), '实际板上 JPEG 解码画面对比：QF30～90',
              fill='#15212f', font=font(34))
    draw.text((28, 60), '左：完整摄像画面    右：同坐标局部放大（各档不是同一时刻）',
              fill='#526173', font=font(20))
    for index, (item, source) in enumerate(zip(results, frames)):
        y = header + index * row_height
        draw.rounded_rectangle((15, y + 3, width - 15, y + row_height - 8),
                               radius=10, fill='white')
        draw.text((32, y + 90), f'QF {item["qf"]}', fill='#15212f', font=font(34))
        draw.text((32, y + 140), f'{item["mean_bytes"] / 1000:.1f} KB',
                  fill='#526173', font=font(25))
        draw.text((32, y + 176), f'{item["raw_to_jpeg_ratio"]:.2f}:1',
                  fill='#526173', font=font(24))
        draw.text((32, y + 219), f'均值 {np.asarray(source).mean():.1f}',
                  fill='#526173', font=font(20))
        overview = source.resize((cw, ch), Image.Resampling.LANCZOS)
        detail = source.crop(crop).resize((cw, ch), Image.Resampling.NEAREST)
        im.paste(overview.convert('RGB'), (280, y + 8))
        im.paste(detail.convert('RGB'), (875, y + 8))
        draw.rectangle((279, y + 7, 280 + cw, y + 8 + ch), outline='#d3dce6', width=2)
        draw.rectangle((874, y + 7, 875 + cw, y + 8 + ch), outline='#d3dce6', width=2)
    out = CAPTURE / 'visual_comparison.png'
    im.save(out)
    print(out)


def main():
    global CAPTURE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-dir', type=Path, default=CAPTURE)
    parser.add_argument('--crop', type=int, nargs=4,
                        default=(780, 405, 1340, 720),
                        metavar=('X0', 'Y0', 'X1', 'Y1'))
    args = parser.parse_args()
    CAPTURE = args.capture_dir
    metrics = json.loads((CAPTURE / 'metrics.json').read_text())
    results = metrics['results']
    frames = [restore(item['qf']) for item in results]
    for item, frame in zip(results, frames):
        frame.save(CAPTURE / f'qf{item["qf"]}_reconstructed.png')
    chart(results)
    visual(results, frames, tuple(args.crop))


if __name__ == '__main__':
    main()

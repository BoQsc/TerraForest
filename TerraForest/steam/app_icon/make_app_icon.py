# SPDX-License-Identifier: 0BSD
"""Regenerate the TerraForest app icon (`steam/app_icon/terraforest.ico`).

The mark is original work: a conifer over terraced hills with a low sun, on a
rounded tile so it reads on a dark taskbar and in Explorer's light view. It is
drawn at 1024 px and reduced, then saved with every size Explorer, the taskbar
and alt-tab ask for.

Usage:
    python steam/app_icon/make_app_icon.py            # rewrite the tool's icon
    python steam/app_icon/make_app_icon.py --out other.ico --preview
"""
from pathlib import Path
import argparse
import math

from PIL import Image, ImageDraw

TOOL = Path(__file__).resolve().parent
DEFAULT_OUT = TOOL/'terraforest.ico'
BASE = 1024
SIZES = (256, 128, 64, 48, 32, 24, 16)

SKY_TOP, SKY_BOTTOM = (26, 70, 102), (146, 200, 214)
SUN, FAR, MID, NEAR, PINE = (246, 226, 170), (108, 168, 132), (68, 130, 96), (40, 92, 68), (18, 52, 40)


def vertical_gradient(size, top, bottom):
    image = Image.new('RGBA', (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / (size - 1)
        draw.line((0, y, size, y),
                  fill=tuple(round(top[c] + (bottom[c] - top[c]) * t) for c in range(3)) + (255,))
    return image


def ridge(image, size, base_y, amplitude, phase, color, step=8):
    points = [(0, size)]
    for x in range(0, size + step, step):
        u = x / size
        points.append((x, size * base_y
                       + size * amplitude * math.sin(u * math.pi * 2.1 + phase)
                       + size * amplitude * 0.45 * math.sin(u * math.pi * 5.7 + phase * 2)))
    points.append((size, size))
    ImageDraw.Draw(image).polygon(points, fill=color)


def pine(draw, size):
    """Three stacked tiers left of centre; no trunk, which only muddied 16 px."""
    cx, top, scale = size * 0.44, size * 0.26, size * 0.44
    for i in range(3):
        t = i / 2
        half = scale * (0.28 + 0.26 * t)
        y0 = top + scale * (0.06 + 0.40 * i)
        draw.polygon([(cx, y0), (cx - half, y0 + scale * 0.40),
                      (cx + half, y0 + scale * 0.40)], fill=PINE)


def build(size):
    image = vertical_gradient(size, SKY_TOP, SKY_BOTTOM)
    draw = ImageDraw.Draw(image)
    radius, cx, cy = size * 0.11, size * 0.70, size * 0.20
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=SUN)
    ridge(image, size, 0.60, 0.045, 0.4, FAR)
    ridge(image, size, 0.72, 0.040, 2.2, MID)
    ridge(image, size, 0.85, 0.030, 4.1, NEAR)
    pine(ImageDraw.Draw(image), size)
    return image


def rounded_mask(size, radius_ratio=0.20):
    """Anti-aliased rounded-square alpha mask, drawn at 4x and reduced."""
    scale, big = 4, None
    big = Image.new('L', (size * scale, size * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, size * scale - 1, size * scale - 1),
                                          radius=int(size * scale * radius_ratio), fill=255)
    return big.resize((size, size), Image.LANCZOS)


def render():
    image = build(BASE).convert('RGBA')
    image.putalpha(rounded_mask(BASE))
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT, help='destination .ico')
    parser.add_argument('--preview', action='store_true', help='also write a 256 px PNG beside it')
    args = parser.parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    image = render()
    image.save(args.out, format='ICO', sizes=[(s, s) for s in SIZES])
    if args.preview:
        image.resize((256, 256), Image.LANCZOS).save(args.out.with_name(args.out.stem + '-256.png'))
    print(f'{args.out}: {args.out.stat().st_size:,} bytes, sizes {list(SIZES)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

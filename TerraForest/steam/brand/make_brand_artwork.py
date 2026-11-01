#!/usr/bin/env python3
"""Draw the Steam artwork from brand.json, with no dependencies beyond the stdlib.

The same geometry is used for every size, so the capsule, hero, logo and icon read as
one family. Output is deterministic: the same brand.json always produces the same
bytes, which is what `--check` relies on.

Usage:
    python steam/brand/make_brand_artwork.py            # write steam/artwork/
    python steam/brand/make_brand_artwork.py --out DIR  # somewhere else
    python steam/brand/make_brand_artwork.py --check    # fail if the committed files differ
"""
from pathlib import Path
import argparse
import json
import struct
import sys
import zlib

# This file lives in steam/brand/; the project is two levels up and the artwork one up.
BRAND = Path(__file__).resolve().parent
PROJECT = BRAND.parents[1]
DEFAULT_OUT = BRAND.parent/'artwork'


def colour(text, alpha=255):
    text = text.lstrip('#')
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16), alpha)


class Canvas:
    """Minimal RGBA raster with the few shapes the artwork needs."""

    def __init__(self, width, height, fill=(0, 0, 0, 0)):
        self.width, self.height = width, height
        self.pixels = bytearray(bytes(fill)*(width*height))

    def _blend(self, x, y, colour_rgba):
        if not (0 <= x < self.width and 0 <= y < self.height):
            return
        red, green, blue, alpha = colour_rgba
        offset = (y*self.width + x)*4
        if alpha >= 255:
            self.pixels[offset:offset+4] = bytes((red, green, blue, 255))
            return
        if alpha <= 0:
            return
        src = alpha/255.0
        dst = self.pixels[offset:offset+4]
        self.pixels[offset:offset+4] = bytes((
            int(red*src + dst[0]*(1-src)),
            int(green*src + dst[1]*(1-src)),
            int(blue*src + dst[2]*(1-src)),
            min(255, int(alpha + dst[3]*(1-src)))))

    def fill(self, colour_rgba):
        self.pixels = bytearray(bytes(colour_rgba)*(self.width*self.height))

    def gradient(self, top, bottom):
        for y in range(self.height):
            t = y/max(1, self.height-1)
            row = tuple(int(top[i]*(1-t) + bottom[i]*t) for i in range(4))
            start = y*self.width*4
            self.pixels[start:start+self.width*4] = bytes(row)*self.width

    def rect(self, x0, y0, x1, y1, colour_rgba):
        for y in range(max(0, int(y0)), min(self.height, int(y1))):
            for x in range(max(0, int(x0)), min(self.width, int(x1))):
                self._blend(x, y, colour_rgba)

    def circle(self, cx, cy, radius, colour_rgba):
        for y in range(int(cy-radius), int(cy+radius)+1):
            span = radius*radius - (y-cy)*(y-cy)
            if span <= 0:
                continue
            dx = span**0.5
            self.rect(cx-dx, y, cx+dx, y+1, colour_rgba)

    def triangle(self, apex, base_y, half_width, colour_rgba):
        """Isosceles triangle: apex point, a flat base, given half width there."""
        apex_x, apex_y = apex
        for y in range(int(apex_y), int(base_y)+1):
            t = (y-apex_y)/max(1e-6, base_y-apex_y)
            half = half_width*t
            self.rect(apex_x-half, y, apex_x+half, y+1, colour_rgba)


def conifer(canvas, cx, base_y, height, palette, scale=1.0):
    """A trunk plus three overlapping tiers, each higher and narrower than the last."""
    # Foliage has its own ramp: reusing the ground shades made the lower tiers vanish.
    tones = [colour(c) for c in palette.get('foliage', palette['terraces'])]
    canvas.rect(cx-height*0.035, base_y-height*0.12, cx+height*0.035, base_y, tones[0])
    tiers = ((0.10, 0.42, 0.26), (0.32, 0.66, 0.19), (0.56, 0.92, 0.13))
    for index, (low, apex, half) in enumerate(tiers):
        canvas.triangle((cx, base_y-height*apex), base_y-height*low,
                        height*half*scale, tones[index])


def hill(canvas, base_y, amplitude, shade):
    """A single soft arch; never negative, so the horizon cannot step or shelf."""
    import math
    for x in range(canvas.width):
        crest = base_y - amplitude*math.sin(math.pi*(x/max(1, canvas.width-1)))
        canvas.rect(x, crest, x+1, canvas.height, shade)


def compose(role, width, height, palette):
    paper, panel = colour(palette['background']), colour(palette['panel'])
    sun = colour(palette['sun'])
    shades = [colour(c) for c in palette['terraces']]
    if role == 'logo.png':
        canvas = Canvas(width, height, (0, 0, 0, 0))
        canvas.circle(width*0.70, height*0.26, height*0.09, sun)
        conifer(canvas, width*0.42, height*0.90, height*0.84, palette)
        return canvas
    if role == 'icon.png':
        canvas = Canvas(width, height, panel)
        hill(canvas, height*0.82, height*0.05, shades[1])
        canvas.circle(width*0.72, height*0.22, height*0.10, sun)
        conifer(canvas, width*0.46, height*0.94, height*0.82, palette)
        hill(canvas, height*0.985, height*0.015, shades[2])
        return canvas
    canvas = Canvas(width, height, paper)
    canvas.gradient(paper, colour(palette['accent_deep']))
    if role == 'portrait.png':
        hill(canvas, height*0.72, height*0.05, shades[1])
        hill(canvas, height*0.84, height*0.04, shades[0])
        canvas.circle(width*0.72, height*0.18, width*0.09, sun)
        conifer(canvas, width*0.44, height*0.94, height*0.62, palette)
        hill(canvas, height*0.985, height*0.015, shades[2])
    elif role == 'wide.png':
        hill(canvas, height*0.70, height*0.07, shades[1])
        hill(canvas, height*0.84, height*0.05, shades[0])
        canvas.circle(width*0.78, height*0.20, height*0.11, sun)
        conifer(canvas, width*0.36, height*0.94, height*0.78, palette)
        hill(canvas, height*0.985, height*0.015, shades[2])
    else:  # hero.png
        hill(canvas, height*0.70, height*0.06, shades[1])
        hill(canvas, height*0.86, height*0.04, shades[0])
        canvas.circle(width*0.76, height*0.22, height*0.13, sun)
        conifer(canvas, width*0.28, height*0.94, height*0.78, palette)
        conifer(canvas, width*0.36, height*0.96, height*0.52, palette, scale=0.9)
        hill(canvas, height*0.985, height*0.015, shades[2])
    return canvas


def png_bytes(canvas):
    raw = bytearray()
    for y in range(canvas.height):
        raw += b'\x00'
        raw += canvas.pixels[y*canvas.width*4:(y+1)*canvas.width*4]

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    header = struct.pack('>IIBBBBB', canvas.width, canvas.height, 8, 6, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
            + chunk(b'IDAT', zlib.compress(bytes(raw), 6)) + chunk(b'IEND', b''))


def render(brand):
    sizes, mapping = brand['steam']['artwork_sizes'], brand['steam']['artwork']
    for name, (width, height) in sizes.items():
        if name not in mapping:
            raise SystemExit(f'{name}: declared size has no Steam target name')
        yield name, png_bytes(compose(name, width, height, brand['palette']))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT,
                        help='folder for the PNGs (default: steam/artwork)')
    parser.add_argument('--check', action='store_true',
                        help='compare with the existing files instead of writing')
    args = parser.parse_args()

    brand = json.loads((BRAND/'brand.json').read_text('utf-8'))
    stale = []
    for name, data in render(brand):
        target = args.out/name
        if args.check:
            current = target.read_bytes() if target.is_file() else None
            state = 'same' if current == data else 'differs'
            if current != data:
                stale.append(name)
            print(f'{name:14} {len(data):>7} bytes  {state}')
            continue
        args.out.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        print(f'{name:14} {len(data):>7} bytes  written')
    if args.check and stale:
        print(f'stale    : {", ".join(stale)}; run python steam/brand/make_brand_artwork.py')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

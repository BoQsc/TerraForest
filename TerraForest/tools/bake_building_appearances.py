# SPDX-License-Identifier: 0BSD
"""Reproduce rejected E1 procedural surfaces for historical review only."""
from pathlib import Path
import hashlib
import json
import math
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
NAMES = ('warm_brick', 'pale_plaster', 'limestone', 'timber', 'slate', 'zinc', 'terracotta', 'chalk_trim')
COLORS = ((157, 94, 72), (212, 204, 184), (165, 163, 145), (122, 91, 61), (62, 74, 82), (109, 124, 130), (165, 91, 63), (199, 193, 177))


def pixels(layer, size):
    data = bytearray()
    for y in range(size):
        data.append(0)  # PNG row filter
        v = y / size
        for x in range(size):
            u = x / size
            fine = (((x*1973+y*9277+layer*26699)*1274126177) & 255) / 255 - .5
            broad = math.sin(u*math.tau*3+math.sin(v*math.tau*2)) * math.sin(v*math.tau*4)
            shade = broad*2 + fine*2
            base = COLORS[layer]
            if layer in (0, 2, 4, 6):
                rows = (4, 3, 5, 4)[(0, 2, 4, 6).index(layer)]
                cols = 2 if layer != 4 else 4
                row = int(v*rows)
                bx = (u*cols + (row % 2)*.5) % 1
                by = (v*rows) % 1
                joint = min(bx, 1-bx) < .012 or min(by, 1-by) < .025
                if joint:
                    base = (155, 148, 129) if layer in (0, 2) else tuple(int(c*.7) for c in base)
                else:
                    brick = (int(u*cols+(row % 2)*.5)*13+row*7) % 7-3
                    shade += brick*1.4
                    if layer == 6: shade += math.cos(bx*math.tau)*5
            elif layer == 3:
                bx = (u*4) % 1
                shade += math.sin(v*math.tau*24+math.sin(u*math.tau*4)*3)*2.5
                if min(bx, 1-bx) < .008: shade -= 23
            elif layer == 5:
                bx = (u*4) % 1
                if min(bx, 1-bx) < .015: shade += 14
                shade += math.sin(v*math.tau*2)*2
            data.extend(max(0, min(255, round(c+shade))) for c in base)
    return data


def png(layer, size):
    def chunk(tag, data):
        return struct.pack('>I', len(data))+tag+data+struct.pack('>I', zlib.crc32(tag+data))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>2I5B', size, size, 8, 2, 0, 0, 0))+chunk(b'IDAT', zlib.compress(pixels(layer, size), 9))+chunk(b'IEND', b'')


def main():
    target = ROOT/'reviews/building_expansion/rejected_e1/textures'
    target.mkdir(parents=True, exist_ok=True)
    entries = []
    for layer, name in enumerate(NAMES):
        content = png(layer, 512)
        path = target/(name+'.trtex')
        path.write_bytes(content)
        entries.append({'appearance': layer, 'path': str(path.relative_to(ROOT)).replace('\\', '/'), 'sha256': hashlib.sha256(content).hexdigest()})
    (target/'provenance.json').write_text(json.dumps({'license': 'CC0-1.0', 'author': 'TerraForest contributors', 'source': 'Original mathematical patterns in tools/bake_building_appearances.py; no imported images', 'size': 512, 'version': 1, 'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'assets': entries}, indent=2)+'\n')
    print('BUILDING_APPEARANCES count=8 size=512 failures=0')


if __name__ == '__main__':
    main()

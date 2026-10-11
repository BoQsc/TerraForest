# SPDX-License-Identifier: 0BSD
"""Reproduce original stone albedo/normal PNG payloads; Python standard library only."""
import math
from pathlib import Path
import random
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
SIZE = 256


def noise(grid, x, y):
    count = len(grid)
    x = x * count / SIZE
    y = y * count / SIZE
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x-ix, y-iy
    fx, fy = fx*fx*(3-2*fx), fy*fy*(3-2*fy)
    return ((1-fx)*grid[iy % count][ix % count]+fx*grid[iy % count][(ix+1) % count])*(1-fy)+(grid[(iy+1) % count][ix % count]*(1-fx)+grid[(iy+1) % count][(ix+1) % count]*fx)*fy


def png(path, pixels):
    def chunk(kind, data):
        return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data))
    raw = b''.join(b'\0'+bytes(pixels[y*SIZE*3:(y+1)*SIZE*3]) for y in range(SIZE))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 2, 0, 0, 0))+chunk(b'IDAT', zlib.compress(raw, 9))+chunk(b'IEND', b''))


def main():
    rng = random.Random(1703)
    grids = [[[rng.random() for _ in range(n)] for _ in range(n)] for n in (4, 13, 37, 97)]
    heights = [[sum(noise(g,x,y)*w for g,w in zip(grids, (.5,.27,.15,.08))) for x in range(SIZE)] for y in range(SIZE)]
    color, normal = bytearray(), bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            h = heights[y][x]
            grain = noise(grids[3],x,y)
            mottling = noise(grids[1],x+67,y+31)
            moss = max(0, min(1, (mottling-.53)*7)) * max(0, 1-y/SIZE*1.6)
            rock = [94+h*57+grain*12, 95+h*55+grain*11, 88+h*52+grain*10]
            lichen = max(0, min(1, (noise(grids[2],x+18,y+6)-.69)*6))*.5
            moss_color = [74, 88, 48]
            for c in range(3):
                v = (rock[c]*(1-moss)+moss_color[c]*moss)*(1-lichen)+(167,172,140)[c]*lichen
                color.append(round(max(0,min(255,v))))
            dx = (heights[y][(x+1) % SIZE]-heights[y][(x-1) % SIZE])*3
            dy = (heights[(y+1) % SIZE][x]-heights[(y-1) % SIZE][x])*3
            length = math.sqrt(dx*dx+dy*dy+1)
            for v in (-dx,dy,1):normal.append(round((v/length*.5+.5)*255))
    folder = ROOT/'addons/world_ecosystem/art'
    folder.mkdir(exist_ok=True)
    png(folder/'stone_color.trtex', color)
    png(folder/'stone_normal.trtex', normal)
    print('Baked two original 256x256 woodland stone maps')


if __name__ == '__main__':
    main()

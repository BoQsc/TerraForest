# SPDX-License-Identifier: 0BSD
"""Inspect portable LFP1 landform programs; never modify a saved world."""
import argparse
import json
from pathlib import Path
import math
import struct

KINDS = ('coast', 'ridge', 'lake', 'island', 'woodland', 'clearing')


def inspect(data):
    if len(data) < 40 or len(data) > 40 + 512 * 48:
        raise ValueError('Invalid landform program length')
    magic, version, seed, extent, base, sea, count, reserved = struct.unpack_from('<IIIfffII', data)
    if magic != 0x3150464c or version not in (1, 2) or reserved or not 1 <= count <= 512 or len(data) != 40 + count * 48:
        raise ValueError('Invalid landform program header')
    checksum = 14695981039346656037
    for value in data[:-8]:
        checksum = ((checksum ^ value) * 1099511628211) & ((1 << 64) - 1)
    if struct.unpack_from('<Q', data, len(data)-8)[0] != checksum:
        raise ValueError('Landform checksum mismatch')
    if seed > 0x7fffffff or not all(math.isfinite(v) for v in (extent, base, sea)) or not 256 <= extent <= 2000 or not 45 <= base <= 150 or not 1 <= sea <= base-4:
        raise ValueError('Invalid domain')
    segments, groups, coast = [], {}, []
    for i in range(count):
        kind, identity, *values = struct.unpack_from('<II10f', data, 32+i*48)
        if kind >= len(KINDS) or identity >= 32 or not all(math.isfinite(v) for v in values):
            raise ValueError('Invalid segment')
        ax, az, bx, bz, aw, bw, level, depth, bank, variation = values
        if not (all(0 <= v <= extent for v in (ax, az, bx, bz)) and 2 <= aw <= 256 and 2 <= bw <= 256 and 4 <= bank <= 128 and 0 <= depth <= 100 and sea <= level <= base+100 and 0 <= variation <= .200001 and (ax-bx)**2+(az-bz)**2 >= .0001):
            raise ValueError('Invalid segment bounds')
        attributes = (kind, level, depth, bank, variation)
        if groups.setdefault(identity, attributes) != attributes:
            raise ValueError('Inconsistent feature identity')
        if kind == 0:
            coast.append((identity, ax, az, bx, bz))
        segments.append(dict(kind=KINDS[kind], feature=identity, start=[ax, az, aw], end=[bx, bz, bw], level=level, depth=depth, bank=bank, variation=variation))
    if coast and (len(coast) < 4 or any(a[0] != b[0] or a[3:] != b[1:3] for a, b in zip(coast, coast[1:]+coast[:1]))):
        raise ValueError('Open coast chain')
    return dict(schema='terraforest.landform-program.v1', kernel_version=version, bytes=len(data), seed=seed, extent=extent, base_height=base, sea_level=sea, segments=segments)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('program', type=Path)
    parser.add_argument('--json', action='store_true', help='Full editable inspection view on stdout; source authoring stays in the module library')
    args = parser.parse_args()
    if args.program.stat().st_size > 24616:
        raise ValueError('Program exceeds the bounded format')
    result = inspect(args.program.read_bytes())
    print(json.dumps(result if args.json else {**{k:v for k,v in result.items() if k!='segments'}, 'segments':len(result['segments']), 'features':len({s['feature'] for s in result['segments']})}, indent=2))


if __name__ == '__main__':
    main()

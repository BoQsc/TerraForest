#!/usr/bin/env python3
# SPDX-License-Identifier: 0BSD
"""Bake original JSON lake guides into bounded native constants; no world output.

This is an authoring compiler. Runtime generation never parses these JSON knots.
The generated header is versioned with immutable terrain 37 and its source digest.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'addons/world_runtime/assets/island_landforms_v37.json'
OUTPUT = ROOT/'addons/world_runtime/native/island_lake_modules.hpp'
NAMES = ('winding_valley', 'branching_basin', 'horseshoe_basin')


def compile_header():
    raw=SOURCE.read_bytes();library=json.loads(raw)
    lines=['// SPDX-License-Identifier: CC0-1.0',
           '// Generated original TerraForest authoring constants; source CC0 library.',
           '// Immutable terrain 37. Revisions require a new terrain identity.',
           '// Source SHA-256: '+hashlib.sha256(raw).hexdigest(), '#pragma once',
           'namespace terraforest::landforms {',
           'struct GuideSegment {float ax,az,aw,bx,bz,bw;};']
    for name in NAMES:
        module=library['modules'][name];paths=module['paths']
        ex=max(abs(p[0])+p[2] for path in paths for p in path)*1.04
        ez=max(abs(p[1])+p[2] for path in paths for p in path)*1.04
        segments=[]
        for path in paths:
            def point(i):return path[max(0,min(len(path)-1,i))]
            for j in range(len(path)-1):
                previous=point(j)
                for step in range(1,9):
                    t=step/8
                    a,b,c,d=[point(j+k) for k in (-1,0,1,2)]
                    current=point(j+1) if step==8 else [(.5*((2*b[k])+(-a[k]+c[k])*t+(2*a[k]-5*b[k]+4*c[k]-d[k])*t*t+(-a[k]+3*b[k]-3*c[k]+d[k])*t*t*t)) for k in range(3)]
                    segments.append([previous[0]/ex,previous[1]/ez,previous[2]/ez,current[0]/ex,current[1]/ez,current[2]/ez]);previous=current
        assert 0<len(segments)<=128
        lines.append('inline constexpr GuideSegment '+name+'[] = {')
        lines += [' {'+','.join(f'{v:.9f}f' for v in values)+'},' for values in segments]
        lines.append('};')
    lines+=['struct Guide {const GuideSegment* segments; unsigned count;};',
            'inline constexpr Guide island_guides[] = {'+','.join('{'+n+',sizeof('+n+')/sizeof(GuideSegment)}' for n in NAMES)+'};','}']
    return '\n'.join(lines)+'\n'


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    text=compile_header()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text()!=text:raise SystemExit('Island module constants are stale')
        print('Island module constants match their JSON authoring source')
    else:OUTPUT.write_text(text)

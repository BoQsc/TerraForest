"""Verify bounded vertical reconstruction against unchanged full-height surfaces."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
from bootstrap_native import ROOT, CACHE, bootstrap

info = bootstrap()
native = ROOT / 'addons/volumetric_terrain/native'
source = ROOT / 'tests/native/terrain_brick_probe.cpp'
folder = ROOT / '.build/brick_probe'
folder.mkdir(exist_ok=True)
exe = folder / 'probe.exe'
command = [info['zig'], 'c++', '-target', 'x86_64-windows-gnu', '-std=c++17', '-O2',
           '-fno-exceptions', '-fno-sanitize=undefined', '-ffp-contract=off',
           '-DTERRAFOREST_TYPED_BRIDGE', '-I', str(native), str(source), str(native / 'core.cpp'), '-o', str(exe)]
env = os.environ.copy()
env['ZIG_GLOBAL_CACHE_DIR'] = str(CACHE / 'zig-global-cache')
env['ZIG_LOCAL_CACHE_DIR'] = str(ROOT / '.build/zig-local-cache')
subprocess.run(command, check=True, env=env, timeout=120)
run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=120)
rows = [json.loads(line) for line in run.stdout.splitlines()]
files = [source, Path(__file__).resolve(), native / 'core.cpp', native / 'core.h', native / 'platform.h',
         native / 'geometry_regions.hpp', *sorted((native / 'experimental').glob('*.hpp'))]
report = dict(rows=rows, exit_code=run.returncode, stderr=run.stderr, complete=len(rows) == 18,
              adoption_qualified=False, build_command=command, toolchain_lock_sha256=info['lock_sha256'],
              source_hashes={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
              scope='Oriented triangle and normal bit parity, aligned/unaligned vertical partitions, and '
                    'local invalidation against full-height reconstruction. Three sites, four successive '
                    'edits per site, single timing observation per case. No runtime streaming, snapshots, '
                    'LOD, shading, materials, collision publication, GPU upload or FPS qualification. '
                    'Render bytes estimate existing 56-byte vertices plus indices; normals duplicate at brick joins.')
path = ROOT / 'reports/terrain_bricks.json'
path.write_text(json.dumps(report, indent=2) + '\n')
for row in rows:
    print(json.dumps(row))
print('Native exit:', run.returncode, run.stderr)
raise SystemExit(bool(run.returncode or not report['complete']))

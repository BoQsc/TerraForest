"""Measure 256 m candidate aggregation and local replacement, without launching Godot."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
from bootstrap_native import ROOT, CACHE, bootstrap

info = bootstrap()
native = ROOT / 'addons/volumetric_terrain/native'
source = ROOT / 'tests/native/terrain_region_aggregate_probe.cpp'
vendor = ROOT / 'tests/native/vendor/meshoptimizer'
manifest = json.loads((vendor / 'manifest.json').read_text())
for name, digest in manifest['files'].items():
    assert hashlib.sha256((vendor / name).read_bytes()).hexdigest() == digest, name
folder = ROOT / '.build/region_aggregate_probe'
folder.mkdir(exist_ok=True)
exe = folder / 'probe.exe'
command = [info['zig'], 'c++', '-target', 'x86_64-windows-gnu', '-std=c++17', '-O2',
           '-fno-exceptions', '-fno-sanitize=undefined', '-ffp-contract=off',
           '-DTERRAFOREST_TYPED_BRIDGE', '-I', str(native), '-I', str(vendor),
           str(source), str(native / 'core.cpp'),
           *[str(vendor / name) for name in ['simplifier.cpp', 'allocator.cpp', 'indexgenerator.cpp']],
           '-o', str(exe)]
env = os.environ.copy()
env['ZIG_GLOBAL_CACHE_DIR'] = str(CACHE / 'zig-global-cache')
env['ZIG_LOCAL_CACHE_DIR'] = str(ROOT / '.build/zig-local-cache')
subprocess.run(command, check=True, env=env, timeout=120)
run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=120)
rows = [json.loads(line) for line in run.stdout.splitlines()]
files = [source, Path(__file__).resolve(), native / 'core.cpp', native / 'core.h',
         native / 'platform.h', native / 'geometry_regions.hpp', *sorted((native / 'experimental').glob('*.hpp'))]
report = dict(rows=rows, exit_code=run.returncode, stderr=run.stderr,
              complete=len(rows) == 8, adoption_qualified=False, build_command=command,
              toolchain_lock_sha256=info['lock_sha256'], vendor=manifest,
              source_hashes={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
              scope='Two 256 m areas, 64 regions each; coarse border-locked geometry replaced locally by fine geometry. '
                    'Exact boundary/overused-edge multiset agreement and fresh geometry/normal reconstruction oracle. '
                    'One observation per case. Simplification error/material preservation NOT qualified. '
                    'Local timing includes probe boundary maps, excludes snapshot capture, shading, packing, '
                    'render batching/upload, retirement and collision publication. Legacy timing uses build_patch. '
                    'No FPS, endurance, runtime cache or complete edit-latency claim.')
path = ROOT / 'reports/terrain_region_aggregate.json'
path.write_text(json.dumps(report, indent=2) + '\n')
for row in rows:
    print(json.dumps(row))
if run.stderr:
    print(run.stderr)
raise SystemExit(bool(run.returncode or not report['complete']))

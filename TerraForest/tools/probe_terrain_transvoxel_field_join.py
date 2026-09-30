"""Check single-face 2:1 transitions in real terrain, without launching Godot."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
from bootstrap_native import ROOT, CACHE, bootstrap

vendor = ROOT / 'tests/native/vendor/transvoxel'
manifest = json.loads((vendor / 'manifest.json').read_text())
for name, digest in manifest['files'].items():
    assert hashlib.sha256((vendor / name).read_bytes()).hexdigest() == digest, name
info = bootstrap()
native = ROOT / 'addons/volumetric_terrain/native'
source = ROOT / 'tests/native/terrain_transvoxel_field_join_probe.cpp'
folder = ROOT / '.build/transvoxel_field_join_probe'
folder.mkdir(exist_ok=True)
exe = folder / 'probe.exe'
command = [info['zig'], 'c++', '-target', 'x86_64-windows-gnu', '-std=c++17', '-O2',
           '-fno-exceptions', '-fno-sanitize=undefined', '-ffp-contract=off',
           '-DTERRAFOREST_TYPED_BRIDGE', '-I', str(native), str(source),
           str(native / 'core.cpp'), '-o', str(exe)]
env = os.environ.copy()
env['ZIG_GLOBAL_CACHE_DIR'] = str(CACHE / 'zig-global-cache')
env['ZIG_LOCAL_CACHE_DIR'] = str(ROOT / '.build/zig-local-cache')
subprocess.run(command, check=True, env=env, timeout=120)
run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=120)
rows = [json.loads(line) for line in run.stdout.splitlines()]
files = [source, Path(__file__).resolve(), ROOT / 'tests/native/transvoxel_probe_cells.hpp',
         native / 'core.cpp', *sorted(native.glob('*.h')), *sorted(native.glob('*.hpp'))]
report = dict(rows=rows, exit_code=run.returncode, stderr=run.stderr, complete=len(rows) == 96,
              adoption_qualified=False, vendor=manifest, build_command=command,
              toolchain_lock_sha256=info['lock_sha256'],
              source_hashes={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
              scope='Two real terrain sites, before/after excavation, six faces, steps 1/2/4/8. Single planar 2:1 join: fine plane shifted inward step/4, coarse plane fixed. Raw World.sample densities; diagnostic trilinear density residual is NOT distance or a certified error bound. No multiple-face corner transitions, zero-density qualification, vertex topology, normals, physics, rendering or performance certification.')
(ROOT / 'reports/terrain_transvoxel_field_join.json').write_text(json.dumps(report, indent=2) + '\n')
for row in rows:
    print(json.dumps(row))
if run.stderr:
    print(run.stderr)
raise SystemExit(bool(run.returncode or not report['complete']))

"""Check six-face transition edges and corners, without launching Godot."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
from bootstrap_native import ROOT, CACHE, bootstrap

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--unprojected', action='store_true', help='Retain inward-only displacement as the comparison')
args = parser.parse_args()

vendor = ROOT / 'tests/native/vendor/transvoxel'
manifest = json.loads((vendor / 'manifest.json').read_text())
for name, digest in manifest['files'].items():
    assert hashlib.sha256((vendor / name).read_bytes()).hexdigest() == digest, name
info = bootstrap()
native = ROOT / 'addons/volumetric_terrain/native'
source = ROOT / 'tests/native/terrain_transvoxel_corner_probe.cpp'
folder = ROOT / '.build/transvoxel_corner_probe'
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
run_command = [str(exe), *(['--unprojected'] if args.unprojected else [])]
run = subprocess.run(run_command, capture_output=True, text=True, timeout=120)
rows = [json.loads(line) for line in run.stdout.splitlines()]
files = [source, Path(__file__).resolve(), ROOT / 'tests/native/transvoxel_probe_cells.hpp',
         native / 'core.cpp', *sorted(native.glob('*.h')), *sorted(native.glob('*.hpp'))]
report = dict(rows=rows, exit_code=run.returncode, stderr=run.stderr, complete=len(rows) == 56,
              adoption_qualified=False, vendor=manifest, build_command=command,
              run_command=run_command, normal_projection=not args.unprojected,
              toolchain_lock_sha256=info['lock_sha256'],
              source_hashes={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
              scope='Full fine cube with all six transition faces and complete coarse shell. 32 synthetic plane/hash/sphere cases plus two real sites at steps 1/2/4, with successful interior/face/corner excavations. Finest mesh must change after each edit. Exact edge/winding/degeneracy and vertex-link checks. Inward quarter-step boundary displacement projected along the tangent using shared central-difference gradients. Planes/spheres measure distance at mesh vertices/centroids; sphere coverage uses 312 angular samples, not a certified Hausdorff bound. Negative distance metrics mean not applicable. No adaptive neighbor masks, normals, physics, streaming, or performance qualification.')
(ROOT / ('reports/terrain_transvoxel_corner' + ('_unprojected' if args.unprojected else '') + '.json')).write_text(json.dumps(report, indent=2) + '\n')
for row in rows:
    print(json.dumps(row))
if run.stderr:
    print(run.stderr)
raise SystemExit(bool(run.returncode or not report['complete']))

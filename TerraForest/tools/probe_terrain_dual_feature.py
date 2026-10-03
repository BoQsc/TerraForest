"""Test an independent table-free adaptive dual prototype and local edit scaling."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
from bootstrap_native import ROOT, CACHE, bootstrap

info = bootstrap()
native = ROOT / 'addons/volumetric_terrain/native'
source = ROOT / 'tests/native/terrain_dual_feature_probe.cpp'
folder = ROOT / '.build/dual_feature_probe'
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
files = [source, Path(__file__).resolve(), ROOT / 'tests/native/incremental_dual_probe.hpp', ROOT / 'tests/native/dual_probe_world_field.hpp',
         ROOT / 'tests/native/dual_probe_audit.hpp',
         native / 'core.cpp', *sorted(native.glob('*.h')), *sorted(native.glob('*.hpp'))]
report = dict(rows=rows, exit_code=run.returncode, stderr=run.stderr, complete=len(rows) == 4,
              adoption_qualified=False, build_command=command, toolchain_lock_sha256=info['lock_sha256'],
              source_hashes={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
              scope='Hidden 2.5m-radius cavity inside an 8m coarse cell: analytic field and actual World excavation. Three axis rays compare triangle hits to bracketed density roots. Quarter-metre error gate equals one quarter of requested 1m detail; it is a test target, not a universal visual standard. Missing-hit errors are -1. Default layout is expected to reject; explicit detail must preserve the feature. Meshes are constructed fresh: no incremental layout update, performance acceptance, shape bound, physics, rendering or runtime integration claim.')
(ROOT / 'reports/terrain_dual_feature.json').write_text(json.dumps(report, indent=2) + '\n')
for row in rows:
    print(json.dumps(row))
if run.stderr:
    print(run.stderr)
raise SystemExit(bool(run.returncode or not report['complete']))

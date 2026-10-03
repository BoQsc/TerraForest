"""Test an independent table-free adaptive dual prototype and local edit scaling."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
from bootstrap_native import ROOT, CACHE, bootstrap

info = bootstrap()
native = ROOT / 'addons/volumetric_terrain/native'
source = ROOT / 'tests/native/terrain_incremental_dual_probe.cpp'
folder = ROOT / '.build/incremental_dual_probe'
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
report = dict(rows=rows, exit_code=run.returncode, stderr=run.stderr, complete=len(rows) == 25,
              adoption_qualified=False, build_command=command, toolchain_lock_sha256=info['lock_sha256'],
              source_hashes={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
              scope='Fixed mixed-resolution leaf layout (1m center, 8m surroundings), shared unit edge segments, canonical unit face triangulation, per-component vertices, '
                    'box-constrained regularized QEF and bucket-indexed shared edge runs with reusable sparse crossing storage. '
                    '64 carve/restore cycles check slot ownership, stable capacity after warmup and geometry fingerprints. '
                    'Every shared edge interval is checked against independent unit-segment neighbor lookup. '
                    'Cold stages are layout/indexing/sampling/component fitting. Capacity counters cover edge/dependency arrays, '
                    'excluding allocator/hash-node overhead, transient arrays, field height caches, total process memory and render resources. '
                    'Unrepresented boundary loops in active cells are rejected; wholly hidden features remain unqualified. '
                    '32/64/128m volumes, synthetic sphere and actual World edits. '
                    'Each incremental update compared bit-for-bit with full reconstruction, plus mesh topology checks. '
                    'Single CPU observations excluding diagnostic audits/oracles. '
                    'No topology-safe coarsening, moving layout, feature-error bounds, memory budget, '
                    'snapshot ownership, physics, GPU publication, FPS or endurance qualification.')
(ROOT / 'reports/terrain_incremental_dual.json').write_text(json.dumps(report, indent=2) + '\n')
for row in rows:
    print(json.dumps(row))
if run.stderr:
    print(run.stderr)
raise SystemExit(bool(run.returncode or not report['complete']))

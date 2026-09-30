"""Exhaustively compare Transvoxel transition interfaces with regular cells."""
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
source = ROOT / 'tests/native/terrain_transvoxel_join_probe.cpp'
folder = ROOT / '.build/transvoxel_join_probe'
folder.mkdir(exist_ok=True)
exe = folder / 'probe.exe'
command = [info['zig'], 'c++', '-target', 'x86_64-windows-gnu', '-std=c++17', '-O2',
           '-fno-exceptions', '-fno-sanitize=undefined', '-ffp-contract=off', str(source), '-o', str(exe)]
env = os.environ.copy()
env['ZIG_GLOBAL_CACHE_DIR'] = str(CACHE / 'zig-global-cache')
env['ZIG_LOCAL_CACHE_DIR'] = str(ROOT / '.build/zig-local-cache')
subprocess.run(command, check=True, env=env, timeout=120)
run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
rows = [json.loads(line) for line in run.stdout.splitlines()]
report = dict(rows=rows, exit_code=run.returncode, complete=len(rows) == 30,
              adoption_qualified=False, vendor=manifest, build_command=command,
              source_hashes={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in [source, ROOT / 'tests/native/transvoxel_probe_cells.hpp', Path(__file__).resolve()]},
              scope='512 sign patterns, six face orientations, five magnitude/coordinate sets. '
                    'Profiles 0-2 are nonzero, 3 inserts exact zeros, 4 replaces those zeros by positive half a density quantum. '
                    'Four fine regular cells, one transition slab and one coarse regular cell. '
                    'Exact geometric edge incidence, winding and nondegeneracy. '
                    'Synthetic extruded fields and expanded slab, not world reconstruction, normals, '
                    'corner transition combinations, simplified terrain error, memory or performance qualification.')
(ROOT / 'reports/terrain_transvoxel_joins.json').write_text(json.dumps(report, indent=2) + '\n')
for row in rows:
    print(json.dumps(row))
raise SystemExit(bool(run.returncode or not report['complete']))

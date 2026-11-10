# SPDX-License-Identifier: 0BSD
"""Compare current terrain edits with HEAD using the same native harness/compiler."""
import hashlib
import argparse
import json
import os
import subprocess
import tempfile
import datetime
from pathlib import Path
from bootstrap_native import ROOT, CACHE, bootstrap
from development_storage import admit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', default='HEAD', help='Git revision containing the unchanged core')
    args = parser.parse_args()
    admission = admit(report_bytes=2**20, scratch_bytes=32*2**20, world_bytes=0)
    info = bootstrap()
    native = ROOT/'addons/volumetric_terrain/native'
    harness = ROOT/'tests/native/terrain_explosion_field_probe.cpp'
    baseline_commit = subprocess.check_output(['git', 'rev-parse', '--verify', args.baseline+'^{commit}'], cwd=ROOT, text=True).strip()
    baseline = subprocess.check_output(['git', 'show', baseline_commit+':TerraForest/addons/volumetric_terrain/native/core.cpp'], cwd=ROOT)
    candidate = (native/'core.cpp').read_bytes()
    env = os.environ.copy()
    env['ZIG_GLOBAL_CACHE_DIR'] = str(CACHE/'zig-global-cache')
    env['ZIG_LOCAL_CACHE_DIR'] = str(ROOT/'.build/zig-local-cache')
    report = {'baseline_commit': baseline_commit, 'admission': admission, 'scope': 'Exact serialized fields and edit receipts, four-generator semantic matrix and 256 ordered edits plus four complete mesh packets on generators 1/31; allocation failure rollback and balance. Field and mesh timings are separate; physics/publication/rendering excluded.', 'runs': {}}
    # Receipt-owned temporary compiler products retire after both processes exit.
    with tempfile.TemporaryDirectory(prefix='edit_core_parity_', dir=ROOT/'.build') as temporary:
        for name, source in [('baseline', baseline), ('candidate', candidate), ('baseline_repeat', baseline)]:
            folder = Path(temporary)/name
            folder.mkdir()
            core = folder/'core.cpp'
            core.write_bytes(source)
            exe = folder/'probe.exe'
            command = [info['zig'], 'c++', '-target', 'x86_64-windows-gnu', '-std=c++17', '-O2', '-fno-exceptions', '-fno-sanitize=undefined', '-ffp-contract=off', '-DTERRAFOREST_TYPED_BRIDGE', '-I', str(native), str(harness), str(core), '-o', str(exe)]
            built = subprocess.run(command, capture_output=True, text=True, env=env, timeout=120)
            if built.returncode:
                raise RuntimeError(built.stdout+built.stderr)
            run = subprocess.run([str(exe)], cwd=folder, capture_output=True, text=True, timeout=30)
            report['runs'][name] = {'core_sha256': hashlib.sha256(source).hexdigest(), 'exit_code': run.returncode, 'log': run.stdout+run.stderr, 'hashes': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(folder.glob('*.bin'))}}
    before, after = report['runs']['baseline'], report['runs']['candidate']
    repeated = report['runs']['baseline_repeat']
    report['ok'] = before['exit_code'] == after['exit_code'] == repeated['exit_code'] == 0 and len(before['hashes']) == 14 and before['hashes'] == after['hashes'] == repeated['hashes']
    report['harness_sha256'] = hashlib.sha256(harness.read_bytes()).hexdigest()
    report['included_harness_sha256'] = hashlib.sha256((harness.parent/'terrain_edit_atomicity_probe.cpp').read_bytes()).hexdigest()
    report['source_patch'] = subprocess.check_output(['git','diff','--',
        'addons/volumetric_terrain/native/core.cpp','addons/volumetric_terrain/native/core.h',
        'tests/native/terrain_explosion_field_probe.cpp'],cwd=ROOT,text=True)
    output = ROOT/'reports/checks'/(datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')+'_terrain_edit_core_parity.json')
    output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'ok': report['ok'], 'report': str(output)}))
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

# SPDX-License-Identifier: 0BSD
"""Benchmark a frozen exported build using owned worlds and an external driver."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import uuid
from resource_limits import require_free_space
from run import ROOT, parse_args
from run_godot_check import execute


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--freeze', action='store_true')
    parser.add_argument('--build', required=True, type=Path)
    parser.add_argument('--slot')
    parser.add_argument('--whole-landscape', action='store_true', help='Load-only diagnostic control for the previous landscape barrier')
    parser.add_argument('--observe', action='store_true', help='Record 20 seconds of background completion after first-ready timing')
    parser.add_argument('--repeat', type=int, default=1)
    args = parser.parse_args()
    base = ROOT / 'reports/startup_optimization'
    base.mkdir(exist_ok=True)
    (base / '.gdignore').touch()
    build = args.build.resolve()
    if args.freeze:
        if build.exists() or not build.is_relative_to(base):
            parser.error('Freeze requires a new folder inside reports/startup_optimization')
        files = [ROOT / 'dist/TerraForest.pck', *(ROOT / 'dist/addons').rglob('*.dll')]
        require_free_space(ROOT, sum(p.stat().st_size for p in files))
        build.mkdir(parents=True)
        for source in files:
            target = build / source.relative_to(ROOT / 'dist')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        if (ROOT / 'dist/assets').exists():
            shutil.copytree(ROOT / 'dist/assets', build / 'assets')
        (build / 'manifest.json').write_text(json.dumps({str(p.relative_to(build)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in build.rglob('*') if p.is_file()}, indent=2))
    manifest = json.loads((build / 'manifest.json').read_text())
    for name, digest in manifest.items():
        if hashlib.sha256((build / name).read_bytes()).hexdigest() != digest:
            raise ValueError('Frozen build changed: ' + name)
    if not 1 <= args.repeat <= 10:
        parser.error('Repeat must be 1..10')
    if args.slot and (not args.slot.startswith('StartupBench_') or not args.slot.isidentifier()):
        parser.error('Only owned StartupBench_ worlds can be loaded')
    if args.whole_landscape and not args.slot:
        parser.error('--whole-landscape requires --slot')
    config, _ = parse_args([])
    driver = build / 'startup_benchmark.gd'
    driver.write_bytes((ROOT / 'tests/startup_benchmark.gd').read_bytes())
    for iteration in range(args.repeat):
        slot = args.slot or ('StartupBench_' + uuid.uuid4().hex[:16])
        folder = base / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        folder.mkdir()
        command = [config.godot, '--path', str(build), '--main-pack', str(build / 'TerraForest.pck'),
            '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60',
            '--log-file', str(folder / 'engine.log'), '--script', str(driver), '--',
            '--benchmark-output=' + folder.as_posix(), '--benchmark-slot=' + slot]
        if args.whole_landscape:
            command.append('--benchmark-whole-landscape')
        if args.observe:
            command.append('--benchmark-observe')
        if not args.slot:
            command.append('--benchmark-generate')
        original = subprocess.Popen
        def nonactivating(*positional, **keywords):
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            # Keep the offscreen window drawable: hiding it can stall
            # frame_post_draw during the generation photograph pipeline.
            startup.wShowWindow = 4
            keywords['startupinfo'] = startup
            return original(*positional, **keywords)
        subprocess.Popen = nonactivating
        try:
            result = execute(command, folder, 660, 'STARTUP_BENCHMARK ok=true', require_resource_budget=True)
        finally:
            subprocess.Popen = original
        (folder / 'run.json').write_text(json.dumps({'command': command, 'build_manifest': manifest,
            'driver_sha256': hashlib.sha256(driver.read_bytes()).hexdigest(), 'slot': slot,
            'result': result, 'cache_scope': 'Existing OS and shared derived caches; not a forced cold-cache run'}, indent=2))
        print(('PASS ' if result['passed'] else 'FAIL ') + str(folder), flush=True)
        if not result['passed']:
            raise SystemExit(1)


if __name__ == '__main__':
    main()

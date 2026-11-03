# SPDX-License-Identifier: 0BSD
"""Benchmark a frozen exported build using owned worlds and an external driver."""
import argparse
import datetime
import hashlib
import json
import os
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
    parser.add_argument('--normal-load', action='store_true', help='Open an owned fixture with ordinary map readiness and writable session semantics')
    parser.add_argument('--whole-landscape', action='store_true', help='Load-only diagnostic control for the previous landscape barrier')
    parser.add_argument('--observe', action='store_true', help='Record 20 seconds of background completion after first-ready timing')
    parser.add_argument('--through-control', action='store_true', help='Include normal fly-in/wakeup and report time to player control')
    parser.add_argument('--no-photographs', action='store_true', help='Require the new-world path to publish no optional preview photographs')
    parser.add_argument('--profile', action='store_true', help='Record terrain worker stages and readiness timeline')
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
    if args.normal_load and not args.slot:
        parser.error('--normal-load requires an owned --slot')
    if args.whole_landscape and not args.slot:
        parser.error('--whole-landscape requires --slot')
    config, _ = parse_args([])
    driver = build / 'startup_benchmark.gd'
    driver.write_bytes((ROOT / 'tests/startup_benchmark.gd').read_bytes())
    for iteration in range(args.repeat):
        slot = args.slot or ('StartupBench_' + uuid.uuid4().hex[:16])
        source_root = None
        source_hash = None
        if args.normal_load:
            # Normal play may checkpoint entry state. Use a new owned copy for
            # every run, keeping the source fixture and comparison input intact.
            worlds = Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds'
            source_root = worlds / (args.slot + '.trw')
            source_hash = hashlib.sha256(source_root.read_bytes()).hexdigest()
            slot = 'StartupBench_' + uuid.uuid4().hex[:16]
            for suffix in ['.trw', '.trw.regions', '.trw.models', '.trw.terrain', '.trw.water', '.trw.baselines', '.generation.json', '.presentation.json']:
                source = worlds / (args.slot + suffix)
                target = worlds / (slot + suffix)
                if source.is_dir():
                    shutil.copytree(source, target)
                elif source.is_file():
                    shutil.copy2(source, target)
        folder = base / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        folder.mkdir()
        command = [config.godot, '--path', str(build), '--main-pack', str(build / 'TerraForest.pck'),
            '--windowed', '--position', '-2400,-1600', '--resolution', '1920x1080', '--max-fps', '60',
            '--log-file', str(folder / 'engine.log'), '--script', str(driver), '--',
            '--benchmark-output=' + folder.as_posix(), '--benchmark-slot=' + slot]
        if args.normal_load:
            command.append('--benchmark-normal-load')
        if args.whole_landscape:
            command.append('--benchmark-whole-landscape')
        if args.through_control:
            command.extend(['--benchmark-through-control', '--wakeup-test'])
        if args.no_photographs:
            command.append('--benchmark-no-photographs')
        if args.profile:
            command.append('--benchmark-profile')
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
        if source_root is not None:
            result['source_fixture_unchanged'] = hashlib.sha256(source_root.read_bytes()).hexdigest() == source_hash
            result['source_fixture'] = args.slot
            result['source_fixture_sha256'] = source_hash
            result['passed'] = result['passed'] and result['source_fixture_unchanged']
        (folder / 'run.json').write_text(json.dumps({'command': command, 'build_manifest': manifest,
            'driver_sha256': hashlib.sha256(driver.read_bytes()).hexdigest(), 'slot': slot,
            'result': result, 'cache_scope': 'Existing OS and shared derived caches; not a forced cold-cache run'}, indent=2))
        print(('PASS ' if result['passed'] else 'FAIL ') + str(folder), flush=True)
        if not result['passed']:
            raise SystemExit(1)


if __name__ == '__main__':
    main()

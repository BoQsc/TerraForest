# SPDX-License-Identifier: 0BSD
"""Archive obsolete owned test worlds/builds; preserve evidence and user saves."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import time
import subprocess
from functools import lru_cache
from contextlib import contextmanager

from cleanup_generation_copies import lease
from retained_artifacts import (ARCHIVE_BUDGET, CAPTURE_BUDGET, Store, archive,
                               confined, digest, ordinary, restore, retire, tree_bytes)

ROOT = Path(__file__).resolve().parents[1]
SLOT = re.compile(r'StartupBench_FPS_[0-9T]{15,30}\Z')
STARTUP_SLOT = re.compile(r'StartupBench_[0-9a-f]{16,32}\Z')
SUFFIXES = ('.trw', '.trw.regions', '.trw.models', '.trw.water', '.trw.terrain',
            '.trw.baselines', '.trw.bak', '.preview', '.generation.json', '.presentation.json')
CREATORS = dict(Quests='quests_world.gd', Survival='player_survival_world.gd',
                Exploration='exploration_world.gd', Parking='building_parking_world.gd',
                CoalMine='coal_mine_world.gd', Reinforced='door_reinforcement_world.gd',
                HouseLights='house_lights_world.gd', SleeperHomes='house_sleepers_world.gd',
                Expedition='frontier_expedition_world.gd', TraderRide='trader_ride_world.gd',
                TraderClothes='trader_clothes.gd', ClothingLoot='clothing_loot_world.gd')


def command_results(value):
    if isinstance(value, dict):
        if isinstance(value.get('command'), list):
            yield value
        for key, child in value.items():
            if key != 'command':
                yield from command_results(child)
    elif isinstance(value, list):
        for child in value:
            yield from command_results(child)


@lru_cache(maxsize=128)
def committed_driver(root, revision, driver):
    git_root = Path(subprocess.check_output(['git','rev-parse','--show-toplevel'],cwd=root,text=True,stderr=subprocess.PIPE).strip())
    path = (root/'tests'/driver).relative_to(git_root).as_posix()
    return subprocess.check_output(['git','show',revision+':'+path],cwd=root,stderr=subprocess.PIPE).decode('utf-8').replace('\r\n','\n')


def creator_driver(command, run, receipt, family, root):
    expected = CREATORS[family]
    if any(Path(c).name == expected for c in command):return True, []
    # Packaged checks freeze the same driver beside their receipt, replacing
    # only helper resource paths. Require exact equality with its recorded Git
    # revision after undoing that substitution; an arbitrary driver.gd is unsafe.
    frozen = receipt.parent/'driver.gd'
    if str(frozen) not in command and frozen.as_posix() not in command:return False, []
    revision = run.get('revision','')
    if not isinstance(revision,str) or not re.fullmatch('[0-9a-f]{40}',revision):return False, []
    try:
        confined(frozen,root/'reports')
        checksum = digest(frozen)
        attested = run.get('external_driver_sha256',{}).get('driver.gd',run.get('test_sha256'))
        if attested and attested != checksum:return False, []
        normalized = frozen.read_text(encoding='utf-8').replace(receipt.parent.as_posix()+'/', 'res://tests/')
        if normalized != committed_driver(root,revision,expected):return False, []
    except (OSError,ValueError,subprocess.SubprocessError):return False, []
    return True, [dict(path=str(frozen),sha256=checksum)]


def additional_world_records(root):
    """Exact creation receipts and completed drivers, never a name-only match."""
    from development_storage import OWNED_SLOT
    created, latest, protected = {}, {}, set()
    for filename in ('created_slot.json', 'world.json'):
        for receipt in (root/'reports').rglob(filename):
            report = receipt.parent/'run.json'
            if not report.is_file():continue
            try:
                world, run = read(receipt), read(report)
            except (ValueError, OSError):continue
            slot = world.get('slot', '') if isinstance(world, dict) else ''
            if not OWNED_SLOT.fullmatch(slot):continue
            family = slot.split('_')[0]
            if family not in CREATORS:continue
            source = world.get('source_slot')
            if source:protected.add(source)
            for entry in command_results(run):
                command, result = entry['command'], entry.get('result', {})
                if '--session-evidence-dir='+receipt.parent.as_posix() not in command:continue
                if result.get('exit_code') is None:continue
                if slot not in latest or report.stat().st_mtime_ns > latest[slot].stat().st_mtime_ns:
                    latest[slot] = report
                creator, driver_proof = creator_driver(command,run,receipt,family,root)
                generated = (entry.get('phase') in ('create', 'create_originals')
                             or (family == 'Expedition' and run.get('stage') == 'create' and not run.get('reused')))
                cloned = (family in ('TraderRide','TraderClothes','ClothingLoot')
                          and world.get('created') is True and source and run.get('clone') == world
                          and not run.get('resume_report'))
                if creator and (generated or cloned):
                    created.setdefault(slot, (receipt, report, source, family, driver_proof))
    records = []
    for slot, (receipt, creation, source, family, driver_proof) in created.items():
        proof = [dict(path=str(p), sha256=digest(p)) for p in (receipt, creation)] + driver_proof
        records.append((latest[slot], slot, dict(source_slot=source, ownership=proof,
                        created_ns=creation.stat().st_mtime_ns), family))
    return records, protected


def read(path):
    ordinary(path)
    return json.loads(path.read_text(encoding='utf-8'))


@contextmanager
def owned_lease(path, root):
    confined(path.parent, root)
    lock = Path(str(path) + '.lock')
    if lock.exists():
        confined(lock, root)
    with lease(path):
        yield


def no_game_processes():
    # Query only. The Steam launcher is not a gameplay process; never stop it.
    if os.name != 'nt':
        raise OSError('Offline process check is implemented for this Windows workspace only')
    import ctypes
    from ctypes import wintypes as W
    from check_generation_interruption import ProcessEntry
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    api.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
    api.CreateToolhelp32Snapshot.restype = W.HANDLE
    api.Process32FirstW.argtypes = [W.HANDLE, ctypes.POINTER(ProcessEntry)]
    api.Process32NextW.argtypes = [W.HANDLE, ctypes.POINTER(ProcessEntry)]
    api.CloseHandle.argtypes = [W.HANDLE]
    snapshot = api.CreateToolhelp32Snapshot(2, 0)
    if snapshot == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    found = []
    try:
        entry = ProcessEntry(); entry.size = ctypes.sizeof(entry)
        more = api.Process32FirstW(snapshot, ctypes.byref(entry))
        while more:
            name = entry.exe.lower()
            if name != 'godot engine.exe' and any(n in name for n in ('godot', 'terraforest', 'zig.exe', 'clang', 'lld.exe')):
                found.append(dict(pid=entry.pid, name=entry.exe))
            more = api.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        api.CloseHandle(snapshot)
    if found:
        raise OSError('Maintenance requires idle gameplay/builds: ' + json.dumps(found))


def world_candidates(root, worlds, keep=2):
    reports = root / 'reports/performance_changes'
    records, protected, rejected = [], set(), []
    for path in sorted(reports.glob('*/run.json')):
        record = read(path)
        clone = record.get('clone', {})
        if clone.get('source_slot'):
            protected.add(clone['source_slot'])
        slot = clone.get('slot', '')
        command = record.get('command', [])
        if not SLOT.fullmatch(slot) or clone.get('created') is not True or not SLOT.fullmatch(clone.get('source_slot', '')):
            continue
        result = record.get('result', {})
        if '--trace-world-slot=' + slot not in command or (result.get('exit_code') is None and not result.get('launch_error')):
            continue
        if any(Path(c).name == 'frame_trace_world.gd' for c in command) is False:
            continue
        if not world_members_remain(worlds, slot, path):
            continue
        records.append((path, slot, clone, 'fps'))
    for path in sorted((root / 'reports/startup_optimization').glob('*/run.json')):
        record = read(path)
        slot, command = record.get('slot', ''), record.get('command', [])
        result = record.get('result', {})
        source = result.get('source_fixture')
        if source:
            protected.add(source)
        generated, copied = '--benchmark-generate' in command, '--benchmark-normal-load' in command
        if not generated and not copied:
            protected.add(slot)  # Explicit read-only/source benchmark input.
            continue
        if not STARTUP_SLOT.fullmatch(slot) or '--benchmark-slot=' + slot not in command:
            continue
        if not any(Path(c).name == 'startup_benchmark.gd' for c in command):
            continue
        if result.get('exit_code') is None and not result.get('launch_error'):
            continue
        if copied and (not source or result.get('source_fixture_unchanged') is not True):
            continue
        if world_members_remain(worlds, slot, path):
            records.append((path, slot, dict(source_slot=source, generated=generated), 'startup'))
    extra, inputs = additional_world_records(root)
    records.extend(r for r in extra if world_members_remain(worlds, r[1], r[0]))
    protected.update(inputs)
    recent = set()
    if keep:
        for family in {r[3] for r in records}:
            ordered = sorted((r for r in records if r[3] == family),
                             key=lambda r:r[2].get('created_ns',r[0].stat().st_mtime_ns))
            # Inactive non-performance test families need no loose ready copy.
            # All evidence remains in the verified archive; sources/pins below
            # remain protected regardless of age.
            if family in CREATORS and max(r[0].stat().st_mtime_ns for r in ordered) < time.time_ns()-3*86400*10**9:
                continue
            recent.update(r[1] for r in ordered[-keep:])
    candidates = []
    for path, slot, clone, family in records:
        if slot in protected or slot in recent or (worlds / (slot + '.retain')).exists():
            rejected.append(dict(slot=slot, reason='source fixture, recent run, or explicit pin'))
            continue
        if (worlds / (slot + '.clone.lock')).exists():
            rejected.append(dict(slot=slot, reason='clone lock exists'))
            continue
        members = [slot + s for s in SUFFIXES if (worlds / (slot + s)).exists()]
        known = set(members + [slot + '.diagnostic.json', slot + '.trw.lock'])
        unexpected = [p.name for p in worlds.glob(slot + '.*') if p.name not in known]
        if unexpected:
            rejected.append(dict(slot=slot, reason='unknown world members', members=unexpected))
            continue
        changed = False
        for member in members:
            p = confined(worlds / member, worlds)
            files = p.rglob('*') if p.is_dir() else [p]
            for file in files:
                info = ordinary(file)
                if file.is_file() and info.st_mtime_ns > path.stat().st_mtime_ns + 2_000_000_000:
                    changed = True
        if changed:
            rejected.append(dict(slot=slot, reason='modified after captured run; may be a played save'))
            continue
        candidates.append(dict(slot=slot, root=str(worlds), members=members, report=str(path),
                               report_sha256=digest(path), source_slot=clone['source_slot'], family=family,
                               ownership=clone.get('ownership', [])))
    return candidates, rejected


def world_members_remain(worlds, slot, report):
    if (worlds / (slot + '.trw')).exists():
        return True
    # A verified retirement may have removed the canonical file before a crash.
    # archive() rechecks immutable ownership and hashes before resuming deletion.
    return (report.parent / 'world.archive.json').exists() and any(
        (worlds / (slot + suffix)).exists() for suffix in SUFFIXES)


def build_candidates(root, keep=0):
    base = root / 'reports/startup_optimization'
    runs = [(p, read(p)) for p in base.glob('*/run.json')]
    result = []
    for manifest in base.glob('*/manifest.json'):
        build = confined(manifest.parent, base)
        if (build / 'RETAIN_READY').exists():
            continue
        hashes = read(manifest)
        if not isinstance(hashes, dict) or 'TerraForest.pck' not in hashes:
            continue
        resuming = (build / 'build.archive.json').exists()
        if not (build / 'TerraForest.pck').exists() and not resuming:
            continue
        if not any((build / n).exists() for n in hashes if n == 'TerraForest.pck' or n.endswith('.dll')):
            continue
        matching = [p for p, r in runs if r.get('build_manifest') == hashes and str(build / 'TerraForest.pck') in r.get('command', [])]
        if not matching:
            continue
        for name, expected in hashes.items():
            if resuming and not (build / name).exists():
                continue
            path = confined(build / name, build)
            if digest(path) != expected:
                raise ValueError('Historical build changed; retain it: ' + str(path))
        result.append(dict(root=str(build), members=[Path(n).as_posix() for n in hashes] + ['manifest.json'] +
                           (['startup_benchmark.gd'] if (build / 'startup_benchmark.gd').exists() else []),
                           report=str(manifest), report_sha256=digest(manifest), matching_runs=[str(p) for p in matching],
                           last_used_ns=max(p.stat().st_mtime_ns for p in matching)))
    result.sort(key=lambda row:row['last_used_ns'])
    return result[:-keep] if keep else result


def capacity(root):
    evidence = tree_bytes(root / 'reports/performance_changes')
    archived = tree_bytes(root / 'reports/retained_artifacts')
    if evidence + 256 * 2**20 > CAPTURE_BUDGET or archived >= ARCHIVE_BUDGET:
        raise OSError('Development retention budget reached; preserve evidence and archive/review before another capture')
    return dict(capture_bytes=evidence, capture_budget=CAPTURE_BUDGET,
                archived_bytes=archived, archive_budget=ARCHIVE_BUDGET)


def archive_regional_cache(report, root=ROOT, userdata=None):
    """Retain exact completed read-only test cache bytes, outside gameplay."""
    from maintain_terrain_cache import cache_lease
    root, report = Path(root).absolute(), Path(report).absolute()
    confined(report, root / 'reports/checks')
    record = read(report)
    command = record.get('command', [])
    expected = 'user://zombie_regional_' + report.parent.name
    if (not re.fullmatch(r'[0-9]{8}T[0-9]{12}Z', report.parent.name)
            or '--snapshot-readonly' not in command
            or [c for c in command if c.startswith('--derived-cache=')] != ['--derived-cache=' + expected]
            or not any(Path(c).name == 'zombie_regional_world.gd' for c in command)
            or record.get('result', {}).get('exit_code') is None
            or record.get('source_data_unchanged') is not True):
        raise ValueError('Read-only regional cache ownership/source verification is incomplete')
    userdata = Path(userdata or Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest').absolute()
    cache = userdata / expected[7:]
    if not cache.exists():
        return dict(archived=False, reason='No cache remains')
    confined(cache, userdata)
    no_game_processes()
    guard = root / 'reports/retained_artifacts'; guard.mkdir(parents=True, exist_ok=True)
    with owned_lease(guard / 'writer', root), cache_lease(cache):
        members = [p.name for p in cache.iterdir() if p.name != '.terraforest-derived.lock']
        if not members:
            return dict(archived=False, reason='No payload remains')
        for path in cache.rglob('*'):
            info = ordinary(path)
            if path.is_file() and path.name != '.terraforest-derived.lock' and info.st_mtime_ns > report.stat().st_mtime_ns + 2_000_000_000:
                raise ValueError('Regional cache changed after its owning run')
        store = Store(guard / 'chunks')
        manifest = report.parent / 'cache.archive.json'
        data = archive(cache, members, manifest, store, dict(owner='regional_readonly_retention',
                       report=str(report), report_sha256=digest(report)))
        removed = retire(data, store, cache)
    result = dict(archived=True, manifest=str(manifest), removed_bytes=removed)
    (report.parent / 'cache_retention.json').write_text(json.dumps(result, indent=2))
    return result


def maintain(root=ROOT, worlds=None, apply=False, builds=False, keep=2, build_keep=0):
    root = Path(root).absolute()
    if not apply:
        return _maintain(root, worlds, False, builds, keep, build_keep)
    no_game_processes()
    guard = root / 'reports/retained_artifacts'
    guard.mkdir(parents=True, exist_ok=True)
    confined(guard, root)
    with owned_lease(guard / 'writer', root):
        return _maintain(root, worlds, True, builds, keep, build_keep)


def _maintain(root=ROOT, worlds=None, apply=False, builds=False, keep=2, build_keep=0):
    root = Path(root).absolute()
    worlds = Path(worlds or Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds').absolute()
    ordinary(root); ordinary(worlds)
    if apply:
        no_game_processes()
    candidates, retained = world_candidates(root, worlds, keep)
    frozen = build_candidates(root, build_keep) if builds else []
    receipt = dict(schema=1, utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), apply=apply,
                   worlds=candidates, builds=frozen, retained_worlds=retained, completed=[], errors=[],
                   scope='Only receipt-owned completed captures and verified frozen builds; all bytes archived before retirement')
    if not apply:
        return receipt
    store = Store(root / 'reports/retained_artifacts/chunks')
    before = store.bytes
    folder = root / 'reports/artifact_retention'
    folder.mkdir(parents=True, exist_ok=True)
    output = folder / (datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.json')
    receipt['receipt'] = str(output)
    output.write_text(json.dumps(receipt, indent=2))
    for kind, rows in [('build', frozen), ('world', candidates)]:
        for row in rows:
            try:
                no_game_processes()
                source = Path(row['root'])
                if digest(Path(row['report'])) != row['report_sha256']:
                    raise ValueError('Ownership receipt changed')
                for proof in row.get('ownership', []):
                    if digest(Path(proof['path'])) != proof['sha256']:
                        raise ValueError('World creation proof changed')
                destination = Path(row['report']).parent / (kind + '.archive.json')
                provenance = dict(owner='performance_retention', kind=kind, report=row['report'], report_sha256=row['report_sha256'])
                if kind == 'world':
                    with owned_lease(worlds / (row['slot'] + '.trw'), worlds):
                        data = archive(source, row['members'], destination, store, provenance)
                        removed = retire(data, store, source)
                else:
                    data = archive(source, row['members'], destination, store, provenance)
                    keep_files = [r['path'] for r in data['files'] if not (r['path'].endswith('.dll') or r['path'] == 'TerraForest.pck')]
                    removed = retire(data, store, source, keep_files)
                receipt['completed'].append(dict(kind=kind, source=row.get('slot', row['root']),
                                                 manifest=str(destination), files=len(data['files']), removed_bytes=removed))
                print('Archived', kind, row.get('slot', Path(row['root']).name), round(removed / 2**20, 1), 'MiB', flush=True)
            except (ValueError, OSError) as error:
                receipt['errors'].append(dict(source=row.get('slot', row['root']), error=str(error)))
                break  # Preserve unresolved work; do not continue an unsafe batch.
            finally:
                receipt['new_archive_bytes'] = store.bytes - before
                output.write_text(json.dumps(receipt, indent=2))
        if receipt['errors']:
            break
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--builds', action='store_true')
    parser.add_argument('--restore', type=Path)
    parser.add_argument('--destination', type=Path)
    args = parser.parse_args()
    if args.restore:
        if not args.destination or args.apply:
            parser.error('Restore requires --destination to a new directory, without --apply')
        no_game_processes()
        print(restore(args.restore, Store(ROOT / 'reports/retained_artifacts/chunks'), args.destination))
        return 0
    result = maintain(apply=args.apply, builds=args.builds)
    print(json.dumps({k:v for k,v in result.items() if k not in ('worlds','builds','retained_worlds','completed')}, indent=2))
    print('Eligible worlds:',len(result['worlds']),'builds:',len(result['builds']), 'retained:',len(result['retained_worlds']))
    if not args.apply:
        output = ROOT / 'reports/artifact_retention_plan.json'
        output.write_text(json.dumps(result, indent=2))
        print('Dry-run plan:', output)
    return int(bool(result['errors']))


if __name__ == '__main__':
    raise SystemExit(main())

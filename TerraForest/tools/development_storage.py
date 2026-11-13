# SPDX-License-Identifier: 0BSD
"""Admission limits for developer outputs, independent of gameplay budgets."""
import json
import os
from pathlib import Path
import stat
import re
from cleanup_generation_copies import lease

from resource_limits import require_free_space

ROOT = Path(__file__).resolve().parents[1]
GIB = 1024**3
LIMITS = {'reports': 4*GIB, 'scratch': 2*GIB, 'archive': 10*GIB,
          'compiler_cache': 4*GIB, 'import_cache': 2*GIB, 'owned_worlds': 3*GIB}
OWNED_SLOT = re.compile(r'(?:StartupBench_(?:FPS_[0-9T]+|[0-9a-f]{16,32})|(?:Quests|Expedition|Parking|CoalMine|Reinforced|Exploration|HouseLights|SleeperHomes|Survival)_1703_[0-9a-f]{8}|(?:TraderRide|ClothingLoot|TraderClothes)_[0-9a-f]{12}|LauncherUI_1703_(?:Fixed|Final))\Z')


def register_worlds(command, folder, root=ROOT):
    """Budget accounting only; registry membership never grants deletion rights."""
    folder, root = Path(folder).absolute(), Path(root).absolute()
    if not folder.resolve().is_relative_to((root/'reports').resolve()):
        return
    slots = set()
    for value in command:
        for prefix in ('--trace-world-slot=','--benchmark-slot='):
            if value.startswith(prefix) and OWNED_SLOT.fullmatch(value[len(prefix):]):
                slots.add(value[len(prefix):])
    evidence_options = [c.split('=',1)[1] for c in command if c.startswith('--session-evidence-dir=')]
    evidence = Path(evidence_options[0]).absolute() if len(evidence_options)==1 else folder
    if (len(evidence_options)==1 and evidence.resolve().is_relative_to((root/'reports').resolve())
            and folder.resolve().is_relative_to(evidence.resolve())):
        for name in ('created_slot.json','world.json'):
            path = evidence/name
            if path.is_file():
                record = json.loads(path.read_text(encoding='utf-8'))
                value = record.get('slot', '')
                if OWNED_SLOT.fullmatch(value):
                    slots.add(value)
    if not slots:
        return
    registry = root/'reports/artifact_retention/owned_worlds.json'
    registry.parent.mkdir(parents=True, exist_ok=True)
    with lease(registry):
        previous = json.loads(registry.read_text()) if registry.exists() else {}
        for slot in slots:
            previous[slot] = {'last_report':str(folder.relative_to(root))}
        temporary = registry.with_suffix('.pending')
        temporary.write_text(json.dumps(previous,indent=2)); temporary.replace(registry)


def owned_world_bytes(root):
    registry = root/'reports/artifact_retention/owned_worlds.json'
    if not registry.exists():
        return 0
    slots = json.loads(registry.read_text())
    worlds = Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'
    total = 0
    if worlds.exists():
        info = worlds.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&0x400:
            raise OSError('Linked world root retained; inspect before capture')
    for slot in slots:
        if not OWNED_SLOT.fullmatch(slot):
            raise ValueError('Invalid test-world budget registry entry')
        for member in worlds.glob(slot+'.*'):
            info = member.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&0x400:
                raise OSError('Linked test world retained; inspect before capture')
            entries = member.rglob('*') if member.is_dir() else [member]
            for path in entries:
                info = path.lstat()
                if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&0x400:
                    raise OSError('Linked test world retained; inspect before capture')
                if stat.S_ISREG(info.st_mode):total += info.st_size
    return total


def usage(root):
    root = Path(root)
    total = dict.fromkeys(LIMITS, 0)
    total['owned_worlds'] = owned_world_bytes(root)
    for name in ('reports', '.build', '.godot'):
        base = root/name
        if not base.exists():
            continue
        info = base.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&0x400:
            raise OSError('Development-output root is linked; inspect it before capture')
        for folder, dirs, files in os.walk(base, followlinks=False):
            directory = Path(folder)
            dirs[:] = [n for n in dirs if not ((directory/n).lstat().st_file_attributes & 0x400)] if os.name == 'nt' else [n for n in dirs if not (directory/n).is_symlink()]
            rel = directory.relative_to(base).parts
            category = ('archive' if name == 'reports' and rel and rel[0] == 'retained_artifacts' else
                        'reports' if name == 'reports' else
                        'import_cache' if name == '.godot' else
                        'compiler_cache' if rel and rel[0] in ('native','zig-local-cache','zig-global-cache') else 'scratch')
            for filename in files:
                info = (directory/filename).lstat()
                if stat.S_ISREG(info.st_mode) and not getattr(info,'st_file_attributes',0)&0x400:
                    total[category] += info.st_size
    return total


def admit(root=ROOT, report_bytes=256*2**20, scratch_bytes=0, limits=None, world_bytes=128*2**20):
    if report_bytes < 0 or scratch_bytes < 0 or world_bytes < 0:
        raise ValueError('Planned output must be nonnegative')
    limits = LIMITS if limits is None else limits
    require_free_space(root, report_bytes + scratch_bytes + world_bytes)
    current = usage(root)
    planned = dict(current)
    planned['reports'] += report_bytes
    planned['scratch'] += scratch_bytes
    planned['owned_worlds'] += world_bytes
    excess = {k:dict(bytes=planned[k], limit=v) for k,v in limits.items() if planned[k] > v}
    if excess:
        raise OSError('Development output budget reached; verify backup and retire obsolete outputs before new work: ' + json.dumps(excess))
    return dict(bytes=current, limits=limits, planned_report_bytes=report_bytes,
                planned_scratch_bytes=scratch_bytes, planned_world_bytes=world_bytes)


if __name__ == '__main__':
    print(json.dumps(dict(bytes=usage(ROOT),limits=LIMITS),indent=2))

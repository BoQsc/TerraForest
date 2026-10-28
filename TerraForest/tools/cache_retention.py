"""Automatic temporary-check cache retention; evidence and saves are never quota victims."""
import datetime
import json
import os
from pathlib import Path
import re
import time

from maintain_terrain_cache import cache_lease, inspect, ordinary, plan, remove_verified
from prune_successful_test_caches import remove_owned_temporary_cache
from resource_limits import load_budgets

ROOT = Path(__file__).resolve().parents[1]
NAME = re.compile(r'[a-z][a-z0-9_]{0,63}_[0-9a-f]{32}\Z')


def cache_size(path):
    total = 0
    if not path.exists():
        return total
    for folder, directories, files in os.walk(path, followlinks=False):
        for name in directories:
            if not ordinary(Path(folder) / name, True):
                raise ValueError('Linked test-cache directory retained')
        for name in files:
            child = Path(folder) / name
            if not ordinary(child):
                raise ValueError('Linked test-cache file retained')
            total += child.stat().st_size
    return total


def finalize_cache(command, passed, root=None, registry=None, quota=None):
    options = [value[16:] for value in command if value.startswith('--derived-cache=')]
    if '--temporary' not in command or len(options) != 1 or not options[0].startswith('user://'):
        return {'managed': False}
    name = options[0][7:]
    if not NAME.fullmatch(name):
        return {'managed': False, 'reason': 'Nonunique or legacy cache path retained'}
    root = (root or Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest').absolute()
    registry = registry or ROOT / 'reports/test_cache_registry'
    if not ordinary(root, True):
        raise ValueError('Game-data root is linked')
    root = root.resolve()
    target = root / name
    if target.exists() and (not ordinary(target, True) or target.resolve().parent != root):
        raise ValueError('Test-cache root escapes game data')
    registry.mkdir(parents=True, exist_ok=True)
    record_path = registry / (name + '.json')
    removed = None
    if passed and target.exists():
        with cache_lease(target):
            pass
        removed = remove_owned_temporary_cache(options[0], root)
    record = dict(cache=options[0], passed=passed, bytes=cache_size(target),
                  completed_unix=time.time(), utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    record_path.write_text(json.dumps(record, indent=2), encoding='utf-8')
    records = []
    for path in registry.glob('*.json'):
        if not NAME.fullmatch(path.stem):
            continue
        item = json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(item, dict):
            raise ValueError('Invalid cache registry record: ' + str(path))
        if item.get('cache') != 'user://' + path.stem or item.get('passed') is not False:
            continue
        cache = root / path.stem
        if type(item.get('bytes')) is not int or item['bytes'] < 0 or not isinstance(item.get('completed_unix'), (int, float)):
            raise ValueError('Invalid cache registry size/time: ' + str(path))
        if cache.exists() and ordinary(cache, True) and cache.resolve().parent == root:
            records.append((path, cache, item))
    total = sum(item['bytes'] for _, _, item in records)
    quota = load_budgets()['failed_test_cache_bytes'] if quota is None else quota
    evicted = 0
    for path, cache, item in sorted(records, key=lambda entry: entry[2]['completed_unix']):
        if total <= quota:
            break
        with cache_lease(cache):
            entries, _ = inspect(cache)
            amount = 0
            for entry in plan(entries, max(0, sum(entry.size for entry in entries) - (total - quota))):
                if remove_verified(cache, entry):
                    amount += entry.size
            item['bytes'] = cache_size(cache)
        total -= amount
        evicted += amount
        path.write_text(json.dumps(item, indent=2), encoding='utf-8')
    return dict(managed=True, removed_owned_cache=removed, retained_bytes=cache_size(target),
                failed_cache_bytes=total, failed_cache_budget_bytes=quota, evicted_derived_bytes=evicted,
                over_budget=total > quota, scope='Successful unique temporary caches removed; oldest registered failed TRC packets trimmed; failed logs, images, unknown files and worlds retained')

"""Check installed content size and retained failed-test caches without launching the game."""
import argparse
import json
import os
from pathlib import Path
import shutil

from resource_limits import ROOT, distribution_size, evaluate, load_budgets
from storage_maintenance import maintain
from cache_retention import cache_size


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--distribution', type=Path, default=ROOT / 'dist')
    parser.add_argument('--storage', action='store_true', help='Also inventory the complete derived-cache quota; no deletion')
    args = parser.parse_args()
    checks = evaluate(distribution_bytes=distribution_size(args.distribution))
    free = shutil.disk_usage(ROOT).free
    records = []
    for path in (ROOT / 'reports/test_cache_registry').glob('*.json'):
        record = json.loads(path.read_text(encoding='utf-8'))
        if record.get('passed') is False:
            records.append(record)
    retained = sum(record['bytes'] for record in records)
    limits = load_budgets()
    result = dict(distributable=checks['redistributable'], free_bytes=free,
                  minimum_free_bytes=limits['minimum_free_bytes'], registered_failed_cache_bytes=retained,
                  failed_cache_budget_bytes=limits['failed_test_cache_bytes'], runtime='Not measured by this static check',
                  scope='Installed game content, not source/history. Saved worlds and development evidence are excluded from automatic quotas.')
    result['passed'] = checks['redistributable']['status'] != 'exceeded' and free >= limits['minimum_free_bytes'] and retained <= limits['failed_test_cache_bytes']
    if args.storage:
        cache = maintain(Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest', limits['derived_cache_total_bytes'])
        result['derived_cache'] = cache
        worlds = cache_size(Path(os.environ['APPDATA']) / 'Godot/app_userdata/TerraForest/worlds')
        result['saved_worlds'] = dict(bytes=worlds, warning_bytes=limits['saved_world_warning_bytes'],
                                     status='warning' if worlds >= limits['saved_world_warning_bytes'] else 'within_budget',
                                     action='Report only; never automatically delete or block a player save')
        result['passed'] = result['passed'] and cache['recognized_bytes'] <= limits['derived_cache_total_bytes']
    (ROOT / 'reports/resource_budget_check.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

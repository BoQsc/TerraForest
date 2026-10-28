"""Maintain verified rebuildable terrain packets without deleting saves or evidence."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime
import json
import os
from pathlib import Path
import shutil
import time

from maintain_terrain_cache import cache_lease, inspect, ordinary, plan, remove_verified

ROOT = Path(__file__).resolve().parents[1]
PROTECTED = {"worlds", "logs", "generation_reports", "screenshots"}


def budgets():
    return json.loads((ROOT / "tools/resource_budgets.json").read_text(encoding="utf-8"))


def cache_roots(root):
    root = root.absolute()
    if not ordinary(root, True):
        raise ValueError("Game-data root must be an absolute ordinary directory")
    root = root.resolve()
    for child in sorted(root.iterdir()):
        if child.name.casefold() in PROTECTED or not ordinary(child, True):
            continue
        if (child / ".terraforest-derived.lock").is_file():
            yield child


def maintain(root, budget, apply=False):
    roots = list(cache_roots(root))
    entries = []
    skipped = 0
    owners = {}
    for index, folder in enumerate(roots):
        found, ignored = inspect(folder, verify_headers=False)
        entries.extend(found)
        skipped += ignored
        for entry in found:
            owners[entry.path] = folder
        if index % 40 == 0:
            print(f"Inspected {index + 1}/{len(roots)} cache roots", flush=True)
    selected = plan(entries, budget)
    selected_roots = {}
    for entry in selected:
        selected_roots.setdefault(owners[entry.path], []).append(entry)
    before = shutil.disk_usage(root).free
    removed_bytes = 0
    removed_files = 0
    failures = []
    next_progress = time.monotonic()
    with ThreadPoolExecutor(max_workers=8) as workers:
        for folder, candidates in selected_roots.items():
            if not apply:
                continue
            try:
                with cache_lease(folder):
                    for offset in range(0, len(candidates), 64):
                        batch = candidates[offset:offset + 64]
                        results = workers.map(lambda entry: remove_verified(folder, entry), batch)
                        for entry, removed in zip(batch, results):
                            if removed:
                                removed_bytes += entry.size
                                removed_files += 1
                            else:
                                failures.append(str(entry.path))
            except OSError as error:
                failures.append(str(error))
            if time.monotonic() >= next_progress:
                print(f"Removed {removed_files} verified packets, {removed_bytes / 2**30:.2f} GiB", flush=True)
                next_progress = time.monotonic() + 15
    return dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), root=str(root),
                mode="apply" if apply else "dry_run", budget_bytes=budget, cache_roots=len(roots),
                recognized_files=len(entries), recognized_bytes=sum(entry.size for entry in entries),
                skipped_entries=skipped, planned_bytes=sum(entry.size for entry in selected),
                removed_bytes=removed_bytes, removed_files=removed_files, failures=failures,
                free_before=before, free_after=shutil.disk_usage(root).free,
                scope="Only recognized, identity/digest-verified TRC mesh packets outside protected world/evidence folders; unknown files retained")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(os.environ.get("APPDATA", "")) / "Godot/app_userdata/TerraForest")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    if args.apply and not args.offline:
        parser.error("Stop Godot and use --offline before applying maintenance")
    result = maintain(args.root, budgets()["derived_cache_total_bytes"], args.apply)
    folder = ROOT / "reports/storage_maintenance"
    folder.mkdir(exist_ok=True)
    path = folder / (datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".json")
    path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key != "failures"}, indent=2))
    print("Receipt:", path)
    return int(bool(result["failures"]))


if __name__ == "__main__":
    raise SystemExit(main())

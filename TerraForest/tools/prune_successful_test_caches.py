"""Prune only audited caches from successful temporary tests; dry-run by default."""
import argparse
import datetime
import json
import os
import re
import shutil
import stat
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def ordinary(path):
    information = path.lstat()
    if stat.S_ISLNK(information.st_mode) or getattr(information, "st_file_attributes", 0) & 0x400:
        raise ValueError("Refusing linked cache entry: " + str(path))
    return information


def remove_owned_temporary_cache(cache, root=None):
    if not cache.startswith("user://"):
        raise ValueError("Expected an owned user-data test cache")
    name = cache[7:]
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,63}_[0-9a-f]{32}", name):
        raise ValueError("Expected a unique temporary-test cache name")
    root = (root or Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest").resolve()
    ordinary(root)
    target = root / name
    if not target.exists():
        return None
    identity = ordinary(target).st_ino
    if target.resolve().parent != root or not target.is_dir():
        raise ValueError("Cache escapes its verified root")
    for parent, directories, files in os.walk(target, followlinks=False):
        for child in directories + files:
            ordinary(Path(parent) / child)
    if ordinary(target).st_ino != identity:
        raise ValueError("Cache identity changed")
    shutil.rmtree(target)
    return str(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    options = parser.parse_args()
    root = (Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest").resolve()
    ordinary(root)
    audit = json.loads((ROOT / "reports/verified_temporary_cache_audit.json").read_text())
    targets = []
    for name, entry in audit.items():
        if entry["passed"] is not True:
            continue
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{1,127}", name):
            raise ValueError("Unsafe test-cache name")
        target = root / name
        if not target.exists():
            continue
        original = ordinary(target)
        if not stat.S_ISDIR(original.st_mode) or target.resolve().parent != root:
            raise ValueError("Cache target escapes the verified game-data folder")
        manifest = (ROOT / entry["manifest"]).resolve()
        if not manifest.is_relative_to(ROOT / "reports"):
            raise ValueError("Unexpected manifest path")
        provenance = json.loads(manifest.read_text())
        if provenance.get("result", {}).get("passed") is not True or "--temporary" not in provenance.get("command", []) or provenance.get("cache") != "user://" + name:
            raise ValueError("Test provenance changed")
        for parent, directories, files in os.walk(target, followlinks=False):
            for child in directories + files:
                ordinary(Path(parent) / child)
        targets.append(dict(path=str(target), manifest=entry["manifest"], audited_bytes=entry["bytes"], identity=original.st_ino))
    total = sum(item["audited_bytes"] for item in targets)
    print(f"Verified successful-test caches: {len(targets)}, audited size: {total / 2**30:.2f} GiB", flush=True)
    if not options.apply:
        print("Dry run only. Add --apply to remove these caches. Played worlds, Git, review images and failed tests are excluded.")
        return 0
    if not targets:
        print("No approved caches remain; existing cleanup receipt preserved.")
        return 0
    before = shutil.disk_usage(root).free
    removed = []
    try:
        for item in targets:
            target = Path(item["path"])
            if ordinary(target).st_ino != item["identity"] or target.resolve().parent != root:
                raise ValueError("Cache identity changed after inspection")
            shutil.rmtree(target)
            removed.append(item)
    finally:
        record = dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), scope="Successful temporary tests only", removed=removed,
                      free_before=before, free_after=shutil.disk_usage(root).free)
        (ROOT / "reports/successful_test_cache_cleanup_20261027.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"Removed {len(removed)} caches; reclaimed {(record['free_after'] - before) / 2**30:.2f} GiB.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

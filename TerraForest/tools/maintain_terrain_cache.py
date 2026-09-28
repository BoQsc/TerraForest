"""Offline quota maintenance for rebuildable TRC meshes; dry-run by default.

Stop every Godot instance using this cache before --apply. This is not a runtime
cache owner or a transaction with the terrain worker. Unknown files are retained.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct

HEX = re.compile(r"[0-9a-f]{64}\Z")
SNAPSHOT = re.compile(r"(?:[0-9a-f]{64}|new_seed_1703)\Z")
TILE = re.compile(r"(-?\d+)_(-?\d+)_(-?\d+)\.trc\Z")
MAX_PACKET = 64 * 1024 * 1024
TRC_MAGIC = 0x36435254
MESH_MAGIC = 0x324D5254


def ordinary(path: Path, directory: bool = False) -> bool:
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
        return False  # Includes Windows junctions and other reparse points.
    return stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)


def identity(path: Path) -> tuple[int, ...]:
    info = path.stat(follow_symlinks=False)
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


@dataclass(frozen=True)
class Entry:
    path: Path
    stamp: tuple[int, ...]

    @property
    def size(self) -> int:
        return self.stamp[2]


def header_valid(path: Path, size: int) -> bool:
    match = TILE.fullmatch(path.name)
    if match is None or not 76 <= size <= MAX_PACKET + 40:
        return False
    key = tuple(int(value) for value in match.groups())
    if any(value < -(2**31) or value >= 2**31 for value in key):
        return False
    with path.open("rb") as source:
        header = source.read(76)
    return (len(header) == 76
            and struct.unpack_from("<II", header) == (TRC_MAGIC, size - 40)
            and struct.unpack_from("<IIiii", header, 40) == (MESH_MAGIC, 5, *key))


def inspect(root: Path, max_entries: int = 100_000) -> tuple[list[Entry], int]:
    """Bound depth and enumeration; an incomplete scan must never delete anything."""
    if not ordinary(root, directory=True):
        raise ValueError("Cache root must be an ordinary directory, not a link/junction")
    found: list[Entry] = []
    skipped = 0
    visited = 0

    def walk(directory: Path, depth: int) -> None:
        nonlocal visited, skipped
        with os.scandir(directory) as children:
            for child in children:
                visited += 1
                if visited > max_entries:
                    raise ValueError("Scan limit exceeded; no cleanup performed")
                path = Path(child.path)
                try:
                    pattern = HEX if depth == 0 else SNAPSHOT
                    if depth < 2 and pattern.fullmatch(child.name) and ordinary(path, True):
                        walk(path, depth + 1)
                    elif depth == 2 and ordinary(path) and TILE.fullmatch(child.name):
                        stamp = identity(path)
                        if header_valid(path, stamp[2]) and identity(path) == stamp:
                            found.append(Entry(path, stamp))
                        else:
                            skipped += 1
                    else:
                        skipped += 1
                except OSError:
                    skipped += 1
    walk(root, 0)
    return found, skipped


def plan(entries: list[Entry], budget: int) -> list[Entry]:
    if budget < 0:
        raise ValueError("Budget must not be negative")
    remaining = sum(entry.size for entry in entries)
    selected: list[Entry] = []
    # Oldest write first; reads deliberately do not update timestamps.
    for entry in sorted(entries, key=lambda item: (item.stamp[3], str(item.path))):
        if remaining <= budget:
            break
        selected.append(entry)
        remaining -= entry.size
    return selected


def remove_verified(root: Path, entry: Entry) -> bool:
    """Recheck paths, identity and full digest immediately before deletion."""
    try:
        relative = entry.path.relative_to(root)
        if len(relative.parts) != 3 or not HEX.fullmatch(relative.parts[0]) or not SNAPSHOT.fullmatch(relative.parts[1]):
            return False
        current = root
        for name in ("", *relative.parts[:-1]):
            current = current / name
            if not ordinary(current, True):
                return False
        if not ordinary(entry.path) or entry.path.resolve().parent != current.resolve():
            return False
        if identity(entry.path) != entry.stamp or not header_valid(entry.path, entry.size):
            return False
        with entry.path.open("rb") as source:
            expected = source.read(40)[8:40]
            digest = hashlib.sha256()
            remaining = entry.size - 40
            while remaining:
                data = source.read(min(65536, remaining))
                if not data:
                    return False
                digest.update(data)
                remaining -= len(data)
            if source.read(1) or digest.digest() != expected:
                return False
        if identity(entry.path) != entry.stamp:
            return False
        entry.path.unlink()
        return True
    except (OSError, ValueError):
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="Dedicated terrain_cache directory")
    parser.add_argument("--budget-mib", type=int, default=384)
    parser.add_argument("--max-entries", type=int, default=100_000)
    parser.add_argument("--apply", action="store_true", help="Delete verified candidates; requires --offline")
    parser.add_argument("--offline", action="store_true", help="Assert all processes using this cache are stopped")
    args = parser.parse_args()
    if args.budget_mib < 0 or args.max_entries < 1:
        parser.error("Budget must be nonnegative and scan limit positive")
    if args.apply and not args.offline:
        parser.error("--apply requires --offline; stop all Godot instances using this cache first")
    root = args.root.absolute()
    try:
        entries, skipped = inspect(root, args.max_entries)
        selected = plan(entries, args.budget_mib * 1024 * 1024)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Cache inspection failed: {error}\n")
    removed = sum(entry.size for entry in selected if args.apply and remove_verified(root, entry))
    planned = sum(entry.size for entry in selected)
    print(json.dumps({
        "root": str(root), "mode": "apply" if args.apply else "dry_run",
        "recognized_files": len(entries), "recognized_bytes": sum(entry.size for entry in entries),
        "skipped_entries": skipped, "budget_bytes": args.budget_mib * 1024 * 1024,
        "planned_files": len(selected), "planned_bytes": planned, "removed_bytes": removed,
        "unremoved_planned_bytes": planned - removed if args.apply else 0,
        "note": "Quota covers recognized TRC meshes only; unknown files and directories are retained.",
    }, indent=2))
    return int(args.apply and removed != planned)


if __name__ == "__main__":
    raise SystemExit(main())

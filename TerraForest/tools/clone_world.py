# SPDX-License-Identifier: 0BSD
"""Copy a stable local world plus its region stores without replacing a save."""
import hashlib
import os
from pathlib import Path
import re
import shutil
import uuid


def copy_map_cache(root, source, destination):
    """Optional derived data only; runtime validates exact terrain/code identity."""
    folder = root.parent / "cartography" / "edited"
    source_path = folder / (hashlib.sha256(source.encode()).hexdigest() + ".bin")
    target = folder / (hashlib.sha256(destination.encode()).hexdigest() + ".bin")
    try:
        if target.exists() or not source_path.is_file():
            return False
        if source_path.stat().st_size != 262216:
            return False
        data = source_path.read_bytes()
        if len(data) != 262216 or data[:8] != b"TFEDIT01" or hashlib.sha256(data[:40] + data[72:]).digest() != data[40:72]:
            return False
        temporary = folder / (target.name + ".tmp_" + uuid.uuid4().hex)
        try:
            temporary.write_bytes(data)
            temporary.rename(target)
        finally:
            temporary.unlink(missing_ok=True)
        # Same dedicated cache bound as the engine writer. Never touch world data.
        entries = sorted((p for p in folder.glob("*.bin") if re.fullmatch(r"[0-9a-f]{64}\.bin", p.name) and p != target), key=lambda p: p.stat().st_mtime)
        for old in entries[:max(0, len(entries) + 1 - 64)]:
            old.unlink(missing_ok=True)
        return True
    except OSError:
        return False


def clone_once(root, source, destination):
    root = Path(root).resolve()
    for slot in (source, destination):
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,47}", slot):
            raise ValueError("Invalid world slot")
    if source == destination:
        raise ValueError("Source and destination must differ")
    original = root / (source + ".trw")
    target = root / (destination + ".trw")
    if target.exists():
        return {"created": False, "slot": destination}
    # Serialize first-run launchers; never infer that an existing lock is stale.
    lock = root / (destination + ".clone.lock")
    with lock.open("x", encoding="utf-8") as handle:
        handle.write(str(os.getpid()))
    try:
        if target.exists():
            return {"created": False, "slot": destination}
        data = original.read_bytes()
        if not data:
            raise ValueError("Source world is empty")
        stage = root / (".clone_" + uuid.uuid4().hex)
        stage.mkdir()
        for suffix in (".regions", ".models", ".water", ".terrain"):
            folder = original.with_name(original.name + suffix)
            dest = target.with_name(target.name + suffix)
            if dest.exists():
                raise FileExistsError("Incomplete destination region store; refusing to overwrite: " + str(dest))
            if folder.exists():
                shutil.copytree(folder, stage / suffix[1:])
        # Immutable checkpoint objects can be shared by successive source saves,
        # but reject a changed canonical root rather than mix source generations.
        if original.read_bytes() != data:
            raise RuntimeError("Source world changed during copy; close the game and retry")
        (stage / "world.trw").write_bytes(data)
        for suffix in (".regions", ".models", ".water", ".terrain"):
            folder = stage / suffix[1:]
            if folder.exists():
                folder.rename(target.with_name(target.name + suffix))
        # Publish the canonical root last. Windows rename refuses existing paths.
        (stage / "world.trw").rename(target)
        stage.rmdir()
        return {"created": True, "slot": destination, "source_slot": source,
                "source_sha256": hashlib.sha256(data).hexdigest(),
                "map_cache_copied": copy_map_cache(root, source, destination)}
    finally:
        lock.unlink()

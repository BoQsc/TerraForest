# SPDX-License-Identifier: 0BSD
"""Copy a stable local world plus its region stores without replacing a save."""
import hashlib
import os
from pathlib import Path
import re
import shutil
import uuid


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
        for suffix in (".regions", ".models"):
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
        for suffix in (".regions", ".models"):
            folder = stage / suffix[1:]
            if folder.exists():
                folder.rename(target.with_name(target.name + suffix))
        # Publish the canonical root last. Windows rename refuses existing paths.
        (stage / "world.trw").rename(target)
        stage.rmdir()
        return {"created": True, "slot": destination, "source_slot": source,
                "source_sha256": hashlib.sha256(data).hexdigest()}
    finally:
        lock.unlink()

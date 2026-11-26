# SPDX-License-Identifier: 0BSD
"""Cold-retain Homestead previews and required G-input UI captures, two ready per family."""
import argparse
import json
from pathlib import Path

from development_storage import admit
from maintain_performance_artifacts import ROOT, no_game_processes, owned_lease
from retained_artifacts import Store, archive, confined, digest, retire

FAMILIES = {
    "homestead_pack": ("homestead_01.png",),
    "homestead_02_pack": ("homestead_02.png",),
    "homestead_03_pack": ("homestead_03.png",),
    "homestead_04_pack": ("homestead_04.png",),
    "homestead_05_pack": ("homestead_05.png",),
    "homestead_06_pack": ("homestead_06.png",),
    "homestead_07_pack": ("homestead_07.png",),
    "drop_key_standard": ("backpack.png", "player_settings.png"),
}


def candidates(root=ROOT):
    ready = {family: [] for family in FAMILIES}
    for receipt in sorted((root / "reports/checks").glob("*/run.json")):
        run = json.loads(receipt.read_text(encoding="utf-8"))
        command = run.get("command", [])
        if run.get("result", {}).get("exit_code") is None or "--script" not in command or "--temporary" not in command:
            continue
        index = command.index("--script") + 1
        if index >= len(command):
            continue
        script = command[index]
        family = Path(script).stem
        if family not in FAMILIES or script != "res://tests/" + family + ".gd":
            continue
        folder = confined(receipt.parent, root / "reports/checks")
        if "--check-evidence-dir=" + str(folder) not in command:
            continue
        if any((folder / pin).exists() for pin in (".retain", "RETAIN_READY", "homestead.archive.json")):
            continue
        members = tuple(name for name in FAMILIES[family] if (folder / name).is_file())
        if members:
            ready[family].append((folder, members))
    return [entry for entries in ready.values() for entry in entries[:-2]]


def maintain(apply=False, root=ROOT):
    selected = candidates(root)
    result = dict(keep_ready=2, candidates=[str(folder) for folder, _ in selected], reclaimed_bytes=0, manifests=[])
    if not apply or not selected:
        return result
    admit(root, report_bytes=1024 * 1024, world_bytes=0)
    no_game_processes()
    with owned_lease(root / "reports/retained_artifacts/writer", root):
        store = Store(root / "reports/retained_artifacts/chunks")
        for folder, members in selected:
            no_game_processes()
            if any((folder / pin).exists() for pin in (".retain", "RETAIN_READY")):
                continue
            record = archive(folder, list(members), folder / "homestead.archive.json", store,
                             dict(kind="completed-object-check-captures", run_sha256=digest(folder / "run.json")))
            result["reclaimed_bytes"] += retire(record, store, folder)
            result["manifests"].append(str(folder / "homestead.archive.json"))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    print(json.dumps(maintain(parser.parse_args().apply), indent=2))

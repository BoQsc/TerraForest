"""Compare opt-in burial and gradual road cuts in a read-only Wild_Hills snapshot."""
import hashlib
import json
import os
from pathlib import Path
import uuid

from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata


def source_hashes(worlds):
    result = {}
    for entry in worlds.glob("Wild_Hills*"):
        paths = entry.rglob("*") if entry.is_dir() else [entry]
        for path in paths:
            if path.is_file():
                result[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def main():
    config, _ = parse_args([])
    worlds = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds"
    if not (worlds / "Wild_Hills.trw").is_file():
        raise SystemExit("Wild_Hills is required; no replacement save will be generated.")
    before = source_hashes(worlds)
    folder = ROOT / "reports/road_burial_trial" / uuid.uuid4().hex
    folder.mkdir(parents=True)
    preparation = folder / "prepare"
    preparation.mkdir()
    prepared = execute([str(config.godot), "--path", str(ROOT), "--headless", "--log-file",
                        str(preparation / "engine.log"), "--script", "res://tests/road_burial_trial.gd"],
                       preparation, 180, "ROAD_BURIAL_TRIAL failures=0")
    result = None
    command = []
    if prepared["passed"]:
        command = [str(config.godot), "--path", str(ROOT), "--log-file", str(folder / "engine.log"),
                   "--fullscreen", "--resolution", "1920x1080", "--max-fps", "60",
                   "--script", "res://tests/road_burial_world_preview.gd", "--", "--temporary",
                   "--snapshot-readonly", "--world-slot=Wild_Hills", "--ground-cover", "--no-zombies",
                   "--nearby-first", "--derived-cache=user://road_burial_preview_" + uuid.uuid4().hex,
                   "--burial-evidence=" + str(folder)]
        result = execute(command, folder, 240, "ROAD_BURIAL_WORLD_PREVIEW failures=0")
    unchanged = before == source_hashes(worlds)
    record = {"preparation": prepared, "result": result, "source_unchanged": unchanged,
              "source_files": before, "command": command, **revision_metadata()}
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    passed = prepared["passed"] and result and result["passed"] and unchanged
    print(("PASS " if passed else "FAIL ") + str(folder))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

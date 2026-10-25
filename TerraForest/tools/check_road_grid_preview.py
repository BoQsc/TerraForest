"""Render the opt-in road grading trial without writing to Wild_Hills."""
import hashlib
import json
import os
from pathlib import Path
import uuid

from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata


def main():
    config, _ = parse_args([])
    worlds = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds"
    files = []
    for entry in worlds.glob("Wild_Hills*"):
        files.extend(path for path in entry.rglob("*") if path.is_file()) if entry.is_dir() else files.append(entry)
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
    folder = ROOT / "reports/road_grid_trial" / ("world_" + uuid.uuid4().hex)
    folder.mkdir(parents=True)
    preparation = folder / "prepare"
    preparation.mkdir()
    prepared = execute([str(config.godot), "--path", str(ROOT), "--headless", "--log-file",
                        str(preparation / "engine.log"), "--script", "res://tests/road_grid_trial.gd"],
                       preparation, 180, "ROAD_GRID_TRIAL failures=0")
    if not prepared["passed"]:
        (folder / "run.json").write_text(json.dumps({"preparation": prepared}, indent=2), encoding="utf-8")
        print("FAIL " + str(folder))
        return 1
    command = [str(config.godot), "--path", str(ROOT), "--log-file", str(folder / "engine.log"),
               "--fullscreen", "--resolution", "1920x1080", "--max-fps", "60",
               "--script", "res://tests/road_grid_world_preview.gd", "--", "--temporary",
               "--snapshot-readonly", "--world-slot=Wild_Hills", "--ground-cover", "--no-zombies",
               "--nearby-first", "--derived-cache=user://road_grid_preview_" + uuid.uuid4().hex]
    result = execute(command, folder, 240, "ROAD_GRID_WORLD_PREVIEW failures=0")
    unchanged = all(Path(path).is_file() and hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest for path, digest in before.items())
    record = {"preparation": prepared, "result": result, "source_unchanged": unchanged, "source_files": before, "command": command, **revision_metadata()}
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("PASS " if result["passed"] and unchanged else "FAIL ") + str(folder))
    return 0 if result["passed"] and unchanged else 1


if __name__ == "__main__":
    raise SystemExit(main())

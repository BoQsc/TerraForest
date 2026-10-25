"""Audit the saved problem view and complete planned road network without saving."""
import json
import os
from pathlib import Path
import uuid

from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata
from review_grid_preference import hashes


def main():
    config, _ = parse_args([])
    slot = "GridPreference_1703_f3de49d9"
    worlds = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds"
    if not (worlds / (slot + ".trw")).is_file():
        raise SystemExit("The saved problem review world is required; no replacement will be made.")
    before = {name: hashes(worlds, name) for name in [slot, "Wild_Hills"]}
    folder = ROOT / "reports/grid_network_audit" / uuid.uuid4().hex
    folder.mkdir(parents=True)
    command = [str(config.godot), "--path", str(ROOT), "--log-file", str(folder / "engine.log"),
               "--script", "res://tests/road_grid_network_audit.gd", "--max-fps", "60", "--",
               "--temporary", "--snapshot-readonly", "--world-slot=" + slot, "--no-zombies",
               "--ground-cover", "--derived-cache=user://grid_network_audit_" + uuid.uuid4().hex]
    record = {"command": command, **revision_metadata()}
    result = execute(command, folder, 240, "GRID_NETWORK_AUDIT failures=0")
    unchanged = all(before[name] == hashes(worlds, name) for name in before)
    record.update(result=result, saves_unchanged=unchanged, quality_accepted=False)
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("AUDIT CAPTURED " if result["passed"] and unchanged else "AUDIT FAILED ") + str(folder))
    return 0 if result["passed"] and unchanged else 1


if __name__ == "__main__":
    raise SystemExit(main())

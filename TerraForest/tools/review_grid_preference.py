"""Inspect the old problem locations in the separately generated default-on review world."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import uuid

from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata


def hashes(root, slot):
    result = {}
    for entry in root.glob(slot + "*"):
        for path in entry.rglob("*") if entry.is_dir() else [entry]:
            if path.is_file():
                result[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--play", action="store_true")
    arguments = parser.parse_args()
    config, _ = parse_args([])
    generation = json.loads((ROOT / "reports/road_normalization/generation/result.json").read_text(encoding="utf-8"))
    slot = generation["slot"]
    if generation["failures"] or not slot.startswith("GridPreference_1703_"):
        raise SystemExit("A passing, separately generated grid-preference review world is required.")
    worlds = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds"
    original = hashes(worlds, "Wild_Hills")
    review = hashes(worlds, slot)
    folder = ROOT / "reports/road_normalization" / (("play_" if arguments.play else "audit_") + uuid.uuid4().hex)
    folder.mkdir(parents=True)
    command = [str(config.godot), "--path", str(ROOT), "--log-file", str(folder / "engine.log"),
               "--fullscreen", "--resolution", "1920x1080", "--max-fps", "60",
               "res://reviews/grid_preference/review.tscn", "--", "--world-slot=" + slot,
               "--ground-cover", "--no-zombies", "--nearby-first", "--actors", "--vehicle-fleet"]
    if not arguments.play:
        command.extend(["--grid-review-auto", "--snapshot-readonly", "--temporary",
                        "--derived-cache=user://grid_preference_audit_" + uuid.uuid4().hex])
    else:
        command.append("--human-playtest")
    record = {"slot": slot, "interactive": arguments.play, "command": command, **revision_metadata()}
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print("Review log: " + str(folder), flush=True)
    result = execute(command, folder, None if arguments.play else 240,
                     "GRID_PREFERENCE_PLAYTEST_READY" if arguments.play else "GRID_PREFERENCE_REVIEW failures=0")
    unchanged = original == hashes(worlds, "Wild_Hills")
    review_unchanged = review == hashes(worlds, slot) if not arguments.play else None
    quality = None
    if not arguments.play:
        contact_path = ROOT / "reports/road_normalization/playtest/contact.json"
        if result["passed"] and contact_path.is_file():
            contact = json.loads(contact_path.read_text(encoding="utf-8"))
            quality = contact.get("slot") == slot and contact.get("quality_passed") is True
        else:
            quality = False
    record.update(result=result, original_save_unchanged=unchanged, review_unchanged=review_unchanged,
                  sampled_contact_quality_passed=quality, human_visual_acceptance="pending")
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    passed = result["passed"] and unchanged and (arguments.play or (review_unchanged and quality))
    print(("PASS " if passed else "FAIL ") + str(folder))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

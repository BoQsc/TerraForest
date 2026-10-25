"""Compare generated road grades in one temporary game window, without player saves."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import uuid

from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    options = parser.parse_args()
    config, _ = parse_args([])
    folder = ROOT / "reports/road_frontage_review" / uuid.uuid4().hex
    folder.mkdir(parents=True)
    worlds = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds"
    source_files = [path for entry in worlds.glob("Wild_Hills*")
                    for path in (entry.rglob("*") if entry.is_dir() else [entry]) if path.is_file()]
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_files}
    target = ["--script", "res://tests/road_frontage_world.gd"] if options.check else ["res://reviews/roads/frontage_review.tscn"]
    command = [str(config.godot), "--path", str(ROOT), "--log-file", str(folder / "engine.log"),
               "--fullscreen", "--resolution", "1920x1080", "--max-fps", "60", *target, "--",
               "--temporary", "--world-slot=Road_Grade_Preview", "--world-generator=21", "--world-seed=1703",
               "--ground-cover", "--no-zombies", "--nearby-first",
               "--derived-cache=user://road_grade_preview_" + uuid.uuid4().hex]
    record = {"command": command, "source_files": before, **revision_metadata()}
    manifest = folder / "run.json"
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    if options.check:
        result = execute(command, folder, 240, "ROAD_FRONTAGE_WORLD failures=0")
    else:
        with (folder / "console.log").open("w", encoding="utf-8") as output:
            process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            record["pid"] = process.pid
            manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
            print("Road-grading preview PID", process.pid, "Log:", folder, flush=True)
            result = {"exit_code": process.wait()}
            log = (folder / "console.log").read_text(encoding="utf-8", errors="replace")
            result["passed"] = result["exit_code"] == 0 and "ROAD_FRONTAGE_REVIEW_READY" in log and "SCRIPT ERROR:" not in log and "ERROR:" not in log
    record["result"] = result
    record["source_unchanged"] = all(Path(path).is_file() and hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest for path, digest in before.items())
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    passed = result["passed"] and record["source_unchanged"]
    print(("PASS " if passed else "FAIL ") + str(folder), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

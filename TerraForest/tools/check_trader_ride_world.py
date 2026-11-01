# SPDX-License-Identifier: 0BSD
"""Exercise a full trader ride in a private copy of an owned generated fixture."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import uuid
from clone_world import clone_once
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-report", required=True)
    parser.add_argument("--stage", choices=["inspect", "full", "resume", "depart", "complete", "cancel", "return-resume"], default="full")
    parser.add_argument("--resume-report", help="Reuse only this runner's owned copied fixture")
    args = parser.parse_args()
    source = (ROOT / args.source_report).resolve()
    if (ROOT / "reports/player_survival_world").resolve() not in source.parents:
        parser.error("Source must be an owned survival test report")
    source_slot = json.loads((source / "created_slot.json").read_text())["slot"]
    if not source_slot.startswith("Survival_"):
        parser.error("Source is not an owned fixture")
    folder = ROOT / "reports/trader_ride_world" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    if args.resume_report:
        previous = (ROOT / args.resume_report).resolve()
        if (ROOT / "reports/trader_ride_world").resolve() not in previous.parents:
            parser.error("Resume requires this runner's owned report")
        receipt = json.loads((previous / "world.json").read_text())
        if not receipt["slot"].startswith("TraderRide_"):
            parser.error("Resume slot is not owned by this runner")
        if (previous / "expected.json").exists():
            (folder / "expected.json").write_bytes((previous / "expected.json").read_bytes())
    else:
        slot = "TraderRide_" + uuid.uuid4().hex[:12]
        world_root = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds"
        receipt = clone_once(world_root, source_slot, slot)
    (folder / "world.json").write_text(json.dumps(receipt, indent=2) + "\n")
    config, _ = parse_args([])
    command = [config.godot, "--path", str(ROOT), "--windowed", "--position", "-2400,-1600", "--resolution", "1920x1080", "--max-fps", "30", "--log-file", str(folder / "engine.log"), "--script", "res://tests/trader_ride_world.gd", "--", "--session-evidence-dir=" + folder.as_posix(), "--ride-stage=" + args.stage]
    original = subprocess.Popen
    native_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in sorted((ROOT / "addons").glob("*/bin/*.dll"))}
    source_hashes = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                     for pattern in ["addons/**/*.gd", "demo/*.gd", "vehicle_demo/scripts/*.gd", "tests/trader*.gd"]
                     for path in sorted(ROOT.glob(pattern))}

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        result = execute(command, folder, 180 if args.stage == "inspect" else 1000, "TRADER_RIDE_WORLD checks=", require_resource_budget=True)
    finally:
        subprocess.Popen = original
    record = dict(stage=args.stage, source_report=args.source_report, clone=receipt, native_sha256=native_hashes, source_sha256=source_hashes, command=command, result=result, **revision_metadata())
    (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n")
    print(("PASS " if result["passed"] else "FAIL ") + str(folder))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

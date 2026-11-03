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
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument("--source-report")
    source_group.add_argument("--source-slot", help="Diagnose a saved world only through a new private copy")
    parser.add_argument("--stage", choices=["inspect", "full", "resume", "depart", "complete", "paid-resume", "cancel", "return-resume", "return-recovery"], default="full")
    parser.add_argument("--resume-report", help="Reuse only this runner's owned copied fixture")
    parser.add_argument("--pack", action="store_true", help="Check the exported PCK with matching native libraries")
    parser.add_argument("--executable", action="store_true", help="Use the existing root TerraForest.exe and exported PCK; never replace it")
    args = parser.parse_args()
    packaged = args.pack or args.executable
    config, _ = parse_args([])
    engine = ROOT / "TerraForest.exe" if args.executable else Path(config.godot)
    pack = ROOT / "dist/TerraForest.pck"
    if args.executable and not engine.is_file():
        parser.error("Existing root TerraForest.exe is required")
    if packaged and not pack.is_file():
        parser.error("Exported dist/TerraForest.pck is required")
    # Reject stale packaged native libraries before copying or opening a save.
    native_hashes = verify_pack_native() if packaged else {
        str(path.relative_to(ROOT)): sha256(path)
        for path in sorted((ROOT / "addons").glob("*/bin/*.dll"))}
    metadata = dict(pack=packaged, executable=args.executable)
    if packaged:
        metadata["pack_sha256"] = sha256(pack)
    if args.executable:
        metadata["executable_sha256"] = sha256(engine)
    if args.stage in ("complete", "paid-resume", "return-resume") and not args.resume_report:
        parser.error("This stage requires --resume-report from the prior owned ride run")
    if args.source_slot:
        if args.stage != "return-recovery" or args.resume_report:
            parser.error("--source-slot is restricted to a fresh return-recovery copy")
        source_slot = args.source_slot
    else:
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
    driver = "res://tests/trader_ride_world.gd"
    if packaged:
        # Tests are excluded from export; only the assertion driver and its
        # test base stay external. All gameplay resources resolve in the PCK.
        parent = folder / "window_session_flow.gd"
        parent.write_bytes((ROOT / "tests/window_session_flow.gd").read_bytes())
        script = folder / "driver.gd"
        script.write_text((ROOT / "tests/trader_ride_world.gd").read_text(encoding="utf-8").replace(
            "res://tests/window_session_flow.gd", parent.as_posix()), encoding="utf-8")
        driver = str(script)
        metadata["external_driver_sha256"] = {path.name: sha256(path) for path in (parent, script)}
    command = [str(engine), "--path", str(ROOT / "dist" if packaged else ROOT), "--windowed", "--position", "-2400,-1600", "--resolution", "1920x1080", "--max-fps", "30", "--log-file", str(folder / "engine.log"), "--script", driver, "--", "--session-evidence-dir=" + folder.as_posix(), "--ride-stage=" + args.stage]
    if packaged:
        command[1:1] = ["--main-pack", str(pack)]
    original = subprocess.Popen
    source_hashes = {path.relative_to(ROOT).as_posix(): sha256(path)
                     for pattern in ["addons/**/*.gd", "demo/*.gd", "vehicle_demo/scripts/*.gd", "tests/trader*.gd", "tests/window_session_flow.gd"]
                     for path in sorted(ROOT.glob(pattern))}

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        result = execute(command, folder, 180 if args.stage in ("inspect", "paid-resume", "return-resume") else 1000, "TRADER_RIDE_WORLD checks=", require_resource_budget=True)
    finally:
        subprocess.Popen = original
    record = dict(stage=args.stage, source_report=args.source_report, source_slot=args.source_slot, resume_report=args.resume_report, clone=receipt, native_sha256=native_hashes, source_sha256=source_hashes, command=command, result=result, **metadata, **revision_metadata())
    (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n")
    print(("PASS " if result["passed"] else "FAIL ") + str(folder))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

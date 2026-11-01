# SPDX-License-Identifier: 0BSD
"""Inspect the production trader in a private copy of an owned generated fixture."""
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-report", required=True, help="Owned reports/player_survival_world directory containing created_slot.json")
    parser.add_argument("--pack", action="store_true")
    args = parser.parse_args()
    source = (ROOT / args.source_report).resolve()
    if (ROOT / "reports/player_survival_world").resolve() not in source.parents:
        parser.error("Source must be an owned survival test report")
    source_slot = json.loads((source / "created_slot.json").read_text())["slot"]
    if not source_slot.startswith("Survival_"):parser.error("Source is not an owned fixture")
    folder = ROOT / "reports/trader_clothes" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    slot = "TraderClothes_" + uuid.uuid4().hex[:12]
    world_root = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds"
    receipt = clone_once(world_root, source_slot, slot)
    (folder / "world.json").write_text(json.dumps(receipt, indent=2) + "\n")
    config, _ = parse_args([])
    record = dict(pack=args.pack, source_report=args.source_report, clone=receipt, **revision_metadata())
    script = ROOT / "tests/trader_clothes.gd"
    if args.pack:
        record["native_sha256"] = verify_pack_native()
        record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
        parent = folder / "window_session_flow.gd"
        parent.write_bytes((ROOT / "tests/window_session_flow.gd").read_bytes())
        text = script.read_text().replace("res://tests/window_session_flow.gd", parent.as_posix())
        script = folder / "driver.gd";script.write_text(text)
    command = [config.godot, "--path", str(ROOT / "dist" if args.pack else ROOT), "--windowed", "--position", "-2400,-1600", "--resolution", "1920x1080", "--max-fps", "30", "--log-file", str(folder / "engine.log"), "--script", str(script), "--", "--session-evidence-dir=" + folder.as_posix()]
    if args.pack:command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO();startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        result = execute(command, folder, 180, "TRADER_CLOTHES checks=", require_resource_budget=True)
    finally:
        subprocess.Popen = original
    record.update(command=command, result=result)
    (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n")
    print(("PASS " if result["passed"] else "FAIL ") + str(folder))
    return 0 if result["passed"] else 1


if __name__ == "__main__":raise SystemExit(main())

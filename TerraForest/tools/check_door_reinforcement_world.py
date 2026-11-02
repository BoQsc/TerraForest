# SPDX-License-Identifier: 0BSD
"""Exercise reinforced doors in normal generation and a fresh process; owned saves only."""
import argparse
import datetime
import hashlib
import json
import subprocess

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="store_true")
    args = parser.parse_args()
    config, _ = parse_args([])
    folder = ROOT / "reports/door_reinforcement_world" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    script = ROOT / "tests/door_reinforcement_world.gd"
    record = dict(pack=args.pack, phases=[], **revision_metadata())
    if args.pack:
        record["native_sha256"] = verify_pack_native()
        record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
        parent = folder / "window_session_flow.gd"
        parent.write_bytes((ROOT / "tests/window_session_flow.gd").read_bytes())
        contents = script.read_text().replace("res://tests/window_session_flow.gd", parent.as_posix())
        script = folder / "driver.gd"
        script.write_text(contents, encoding="utf-8")
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        for phase in ["create", "reopen"]:
            destination = folder / phase
            destination.mkdir()
            command = [config.godot, "--path", str(ROOT / "dist" if args.pack else ROOT),
                       "--windowed", "--position", "-2400,-1600", "--resolution", "1920x1080",
                       "--max-fps", "60", "--log-file", str(destination / "engine.log"),
                       "--script", str(script), "--", "--session-evidence-dir=" + folder.as_posix()]
            if args.pack:
                command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
            if phase == "reopen":
                command.append("--door-reopen")
            result = execute(command, destination, 800, "DOOR_REINFORCEMENT_WORLD checks=", require_resource_budget=True)
            record["phases"].append(dict(phase=phase, command=command, result=result))
            record["passed"] = all(row["result"]["passed"] for row in record["phases"])
            (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n")
            print(("PASS " if result["passed"] else "FAIL ") + phase + " " + str(folder), flush=True)
            if not result["passed"]:
                return 1
    finally:
        subprocess.Popen = original
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# SPDX-License-Identifier: 0BSD
"""Nonactivating source review of the woven pack and real equipment transactions."""
import argparse
import datetime
import json
import subprocess
import uuid
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--world", action="store_true", help="Create, equip and reopen a dedicated generated fixture in two processes")
    args = parser.parse_args()
    config, _ = parse_args([])
    engine = config.godot
    folder = ROOT / "reports/woven_clothes" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    slot = "Woven_" + uuid.uuid4().hex[:12]
    jobs = ["create", "restore"] if args.world else ["source"]
    record = dict(slot=slot if args.world else None, results=[], **revision_metadata())
    original = subprocess.Popen

    def nonactivating(*args, **kwargs):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        kwargs["startupinfo"] = startup
        return original(*args, **kwargs)

    subprocess.Popen = nonactivating
    try:
        for job in jobs:
            destination = folder / job
            destination.mkdir()
            script = "woven_clothes_world" if args.world else "woven_clothes"
            command = [engine, "--path", str(ROOT), "--windowed", "--position", "-2400,-1600", "--resolution", "1920x1080", "--max-fps", "30", "--log-file", str(destination / "engine.log"), "--script", "res://tests/" + script + ".gd", "--", "--evidence=" + destination.as_posix(), "--session-evidence-dir=" + destination.as_posix(), "--woven-slot=" + slot]
            if job == "restore":command.append("--restore")
            result = execute(command, destination, 150 if args.world else 120, script.upper() + " checks=", require_resource_budget=True)
            record["results"].append(dict(job=job, command=command, result=result))
            (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n")
            print(("PASS " if result["passed"] else "FAIL ") + str(destination), flush=True)
            if not result["passed"]:return 1
    finally:
        subprocess.Popen = original
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

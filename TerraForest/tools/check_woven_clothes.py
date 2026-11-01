# SPDX-License-Identifier: 0BSD
"""Nonactivating source/package review of clothing and real equipment transactions."""
import argparse
import datetime
import hashlib
import json
import subprocess
import uuid
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--world", action="store_true", help="Create, equip and reopen a dedicated generated fixture in two processes")
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--restore-report", help="Reopen an existing owned clothing fixture without creating another world")
    args = parser.parse_args()
    config, _ = parse_args([])
    engine = config.godot
    folder = ROOT / "reports/woven_clothes" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    slot = "Woven_" + uuid.uuid4().hex[:12]
    jobs = ["create", "restore"] if args.world else ["source"]
    if args.restore_report:
        source = (ROOT / args.restore_report).resolve()
        if (ROOT / "reports/woven_clothes").resolve() not in source.parents:
            parser.error("Only owned clothing reports may be reopened")
        slot = json.loads((source / "run.json").read_text())["slot"]
        if not isinstance(slot, str) or not slot.startswith("Woven_") or len(slot) >= 48:
            parser.error("Not an owned clothing fixture")
        args.world = True
        jobs = ["restore"]
    record = dict(pack=args.pack, restore_report=args.restore_report, slot=slot if args.world else None, results=[], **revision_metadata())
    if args.pack:
        record["native_sha256"] = verify_pack_native()
        record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
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
            driver = ROOT / "tests" / (script + ".gd")
            if args.pack:
                text = driver.read_text(encoding="utf-8")
                if args.world:
                    parent = destination / "window_session_flow.gd"
                    parent.write_bytes((ROOT / "tests/window_session_flow.gd").read_bytes())
                    text = text.replace("res://tests/window_session_flow.gd", parent.as_posix())
                driver = destination / "driver.gd"
                driver.write_text(text, encoding="utf-8")
            command = [engine, "--path", str(ROOT / "dist" if args.pack else ROOT), "--windowed", "--position", "-2400,-1600", "--resolution", "1920x1080", "--max-fps", "30", "--log-file", str(destination / "engine.log"), "--script", str(driver), "--", "--evidence=" + destination.as_posix(), "--session-evidence-dir=" + destination.as_posix(), "--woven-slot=" + slot]
            if args.pack:
                command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
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

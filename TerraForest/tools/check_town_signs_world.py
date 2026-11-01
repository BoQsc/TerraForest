# SPDX-License-Identifier: 0BSD
"""Check ordinary town-sign generation and fresh-process saved-world restoration."""
import argparse
import datetime
import hashlib
import json
import subprocess

from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--restore-report")
    parser.add_argument("--untimed", action="store_true", help="Skip frame samples while other build work runs")
    args = parser.parse_args()
    base = ROOT / "reports/town_signs_world"
    folder = base / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    if args.restore_report:
        source = (ROOT / args.restore_report).resolve()
        if base.resolve() not in source.parents:
            parser.error("Restore only owned town-sign reports")
        receipt = json.loads((source / "slot.json").read_text())
        if not receipt["slot"].startswith("TownSigns_1703_"):
            parser.error("Not an owned sign fixture")
        (folder / "slot.json").write_bytes((source / "slot.json").read_bytes())
    record = dict(pack=args.pack, untimed=args.untimed, phases=[], **revision_metadata())
    record["sign_sources_sha256"] = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                                     for name in ("addons/world_runtime/town_sign_plan.gd",
                                                  "addons/world_runtime/town_signs.gd",
                                                  "tests/town_signs_world.gd")}
    record["native_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sorted((ROOT / "addons").glob("*/bin/*.dll"))}
    script = ROOT / "tests/town_signs_world.gd"
    engine = ROOT / "TerraForest.exe" if args.pack else parse_args([])[0].godot
    if args.pack:
        record["native_sha256"] = verify_pack_native()
        record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
        parent = folder / "window_session_flow.gd"
        parent.write_bytes((ROOT / "tests/window_session_flow.gd").read_bytes())
        driver = folder / "driver.gd"
        driver.write_text(script.read_text().replace("res://tests/window_session_flow.gd", parent.as_posix()), encoding="utf-8")
        script = driver
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        for phase in (["restore"] if args.restore_report else ["create", "restore"]):
            destination = folder / phase
            destination.mkdir()
            command = [str(engine), "--path", str(ROOT / "dist" if args.pack else ROOT),
                       "--windowed", "--position", "-2400,-1600", "--resolution", "1920x1080",
                       "--max-fps", "60", "--log-file", str(destination / "engine.log"),
                       "--script", str(script), "--", "--session-evidence-dir=" + folder.as_posix()]
            if args.pack:
                command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
            if phase == "restore":
                command.append("--reopen-signs")
            if args.untimed:
                command.append("--signs-untimed")
            result = execute(command, destination, 600, "failures=0", require_resource_budget=True)
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

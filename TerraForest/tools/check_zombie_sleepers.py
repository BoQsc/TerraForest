# SPDX-License-Identifier: 0BSD
"""Import or review original sleeper clips without capturing or focusing the pointer."""
import argparse
import datetime
import json
import subprocess

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import execute, verify_pack_native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["import", "review", "poses", "runtime", "state", "impacts"])
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--missing", choices=["forearm_l", "shin_l", "thigh_r"])
    parser.add_argument("--motion", action="store_true")
    args = parser.parse_args()
    if args.pack and args.stage == "import":
        parser.error("Authoring import cannot run from a published pack")
    if args.missing and args.stage != "review":
        parser.error("Missing-limb rendering belongs to review mode")
    if args.motion and (args.stage != "review" or args.missing):
        parser.error("Motion review requires review mode without a missing-limb override")
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/zombie_sleepers" / stamp
    folder.mkdir(parents=True)
    script = {"state": "tests/zombie_sleep_state.gd", "runtime": "tests/zombie_sleeper_runtime.gd", "poses": "tests/zombie_sleepers.gd", "impacts": "tests/zombie_impacts.gd"}.get(args.stage, f"tools/{args.stage}_zombie_sleepers.gd")
    command = [config.godot, "--path", str(ROOT), "--log-file", str(folder / "engine.log"),
               "--max-fps", "60", "--script", "res://" + script]
    if args.stage in ["review", "runtime", "impacts"]:
        command[1:1] = ["--windowed", "--position", "-2400,-1600", "--resolution", "1280x720" if args.motion else "1920x1080"]
        command += ["--", "--review-output=" + folder.as_posix()]
        if args.missing:
            command.append("--review-missing=" + args.missing)
        if args.motion:
            command.append("--review-motion")
    else:
        command.insert(1, "--headless")
        if args.stage in ["poses", "state"]:
            command += ["--", "--sleeper-output=" + folder.as_posix()]
    record = dict(stage=args.stage, pack=args.pack, missing=args.missing, motion=args.motion, **revision_metadata())
    if args.pack:
        record["native_sha256"] = verify_pack_native()
        driver = folder / "driver.gd"
        driver.write_bytes((ROOT / script).read_bytes())
        command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        command[command.index("--path") + 1] = str(ROOT / "dist")
        command[command.index("--script") + 1] = str(driver)
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        marker = "ZOMBIE_SLEEPERS checks=" if args.stage == "poses" else "ZOMBIE_SLEEPERS_" + args.stage.upper()
        result = execute(command, folder, 150 if args.stage in ["runtime", "impacts"] else 90, marker, require_resource_budget=args.stage in ["review", "runtime", "impacts"])
        if args.stage in ["state", "runtime"] and result["passed"]:
            fresh = folder / "fresh"
            fresh.mkdir()
            fresh_command = command.copy()
            fresh_command[fresh_command.index("--log-file") + 1] = str(fresh / "engine.log")
            if args.stage == "runtime":
                fresh_command[fresh_command.index("--review-output=" + folder.as_posix())] = "--review-output=" + fresh.as_posix()
                fresh_command.append("--runtime-read=" + (folder / "runtime_sleep_population.bin").as_posix())
            else:
                fresh_command.append("--sleep-read=" + (folder / "population_sleep.bin").as_posix())
            fresh_result = execute(fresh_command, fresh, 30, marker, require_resource_budget=args.stage == "runtime")
            record["fresh_process"] = fresh_result
            result["passed"] = result["passed"] and fresh_result["passed"]
    finally:
        subprocess.Popen = original
    record.update(command=command, result=result)
    (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(("PASS " if result["passed"] else "FAIL ") + str(folder))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

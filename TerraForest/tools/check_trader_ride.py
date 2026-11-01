# SPDX-License-Identifier: 0BSD
"""Run native road journey contracts with an isolated debug or release library."""
import argparse
import datetime
import hashlib
import json
import shutil
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", action="store_true")
    parser.add_argument("--state", action="store_true", help="Validate persistent service states instead of road routing")
    parser.add_argument("--plan", help="Check a captured generated-world plan.json for intertown connectivity")
    parser.add_argument("--payment", action="store_true", help="Check atomic fares and refunds with the player runtime")
    args = parser.parse_args()
    config, _ = parse_args([])
    variant = "template_release" if args.release else "template_debug"
    name = "trader_ride_payment" if args.payment else "trader_road_plan" if args.plan else "trader_ride_state" if args.state else "trader_road_journey"
    addon_name = "player_runtime" if args.payment else "vehicle_runtime"
    folder = ROOT / "reports" / name / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    project = folder / "project"
    addon = project / "addons" / addon_name
    (addon / "bin").mkdir(parents=True)
    (project / "tests").mkdir()
    (project / "project.godot").write_text('[application]\nconfig/name="Trader road journey contracts"\n', encoding="utf-8")
    source = ROOT / "addons" / addon_name
    library = source / "bin" / (addon_name + ".windows." + variant + ".x86_64.dll")
    shutil.copy2(library, addon / "bin" / library.name)
    descriptor = (source / (addon_name + ".gdextension")).read_text(encoding="utf-8")
    descriptor = descriptor.replace("template_debug", variant).replace("template_release", variant)
    (addon / (addon_name + ".gdextension")).write_text(descriptor, encoding="utf-8")
    script = ROOT / "tests" / (name + ".gd")
    shutil.copy2(script, project / "tests" / script.name)
    command = [config.godot, "--headless", "--path", str(project), "--log-file", str(folder / "engine.log"), "--script", "res://tests/" + name + ".gd"]
    if args.plan:
        plan = (ROOT / args.plan).resolve()
        if (ROOT / "reports/trader_ride_world").resolve() not in plan.parents:
            parser.error("Plan must be captured by the owned trader ride world runner")
        shutil.copy2(plan, folder / "plan.json")
        command += ["--", "--plan=" + (folder / "plan.json").as_posix()]
    result = execute(command, folder, 60, name.upper() + " checks=")
    record = dict(variant=variant, library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(), test_sha256=hashlib.sha256(script.read_bytes()).hexdigest(), command=command, result=result, **revision_metadata())
    (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(("PASS " if result["passed"] else "FAIL ") + str(folder))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

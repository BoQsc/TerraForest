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
    args = parser.parse_args()
    config, _ = parse_args([])
    variant = "template_release" if args.release else "template_debug"
    folder = ROOT / "reports/trader_road_journey" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    project = folder / "project"
    addon = project / "addons/vehicle_runtime"
    (addon / "bin").mkdir(parents=True)
    (project / "tests").mkdir()
    (project / "project.godot").write_text('[application]\nconfig/name="Trader road journey contracts"\n', encoding="utf-8")
    source = ROOT / "addons/vehicle_runtime"
    library = source / "bin" / ("vehicle_runtime.windows." + variant + ".x86_64.dll")
    shutil.copy2(library, addon / "bin" / library.name)
    descriptor = (source / "vehicle_runtime.gdextension").read_text(encoding="utf-8")
    descriptor = descriptor.replace("template_debug", variant).replace("template_release", variant)
    (addon / "vehicle_runtime.gdextension").write_text(descriptor, encoding="utf-8")
    script = ROOT / "tests/trader_road_journey.gd"
    shutil.copy2(script, project / "tests" / script.name)
    command = [config.godot, "--headless", "--path", str(project), "--log-file", str(folder / "engine.log"), "--script", "res://tests/trader_road_journey.gd"]
    result = execute(command, folder, 60, "TRADER_ROAD_JOURNEY checks=")
    record = dict(variant=variant, library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(), test_sha256=hashlib.sha256(script.read_bytes()).hexdigest(), command=command, result=result, **revision_metadata())
    (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(("PASS " if result["passed"] else "FAIL ") + str(folder))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

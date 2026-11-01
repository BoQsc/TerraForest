# SPDX-License-Identifier: 0BSD
"""Small isolated debug/release native contracts; no player saves or asset imports."""
import argparse
import datetime
import hashlib
import json
import shutil
from run import ROOT, parse_args
from play_checkpoint import revision_metadata
from run_godot_check import execute


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", action="store_true")
    args = parser.parse_args()
    config, _ = parse_args([])
    folder = ROOT / "reports/exploration_native" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    project = ROOT
    record = dict(release=args.release, tests=[], libraries={}, **revision_metadata())
    tests = ["arched_excavation", "exploration_layouts", "prefab_model_only"]
    if args.release:
        project = ROOT / ".build/exploration_release"
        project.mkdir(parents=True, exist_ok=True)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Exploration native checks"\n')
        paths = ["addons/exploration/cave_layouts.gd", "addons/exploration/coal_mine.gd", "addons/exploration/coal_resource.gd", "addons/structures/mine_rail_catalog.gd", "addons/exploration/small_locations.poi.json", "addons/world_runtime/generation_earthworks.gd", "addons/volumetric_terrain/mesh_codec.gd", *[f"tests/{name}.gd" for name in tests]]
        for relative in paths:
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        for addon, descriptor, library in [("volumetric_terrain", "terrain_core", "terrain_core.windows.template_release.x86_64.dll"), ("structures", "structures", "structures.windows.template_release.x86_64.dll")]:
            target = project / "addons" / addon
            (target / "bin").mkdir(parents=True, exist_ok=True)
            source = ROOT / "addons" / addon
            shutil.copy2(source / "bin" / library, target / "bin" / library)
            data = (source / (descriptor + ".gdextension")).read_text()
            data = data.replace("template_debug", "template_release").replace("terrain_core.windows.x86_64.dll", "terrain_core.windows.template_release.x86_64.dll")
            (target / (descriptor + ".gdextension")).write_text(data)
            record["libraries"][addon] = hashlib.sha256((target / "bin" / library).read_bytes()).hexdigest()
    for name in tests:
        destination = folder / name
        destination.mkdir()
        command = [config.godot, "--headless", "--path", str(project), "--log-file", str(destination / "engine.log"), "--script", f"res://tests/{name}.gd"]
        result = execute(command, destination, 90, name.upper() + " checks=")
        record["tests"].append(dict(name=name, command=command, result=result))
        print(("PASS " if result["passed"] else "FAIL ") + name, flush=True)
    record["passed"] = all(test["result"]["passed"] for test in record["tests"])
    (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n")
    print(("PASS " if record["passed"] else "FAIL ") + str(folder), flush=True)
    return 0 if record["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

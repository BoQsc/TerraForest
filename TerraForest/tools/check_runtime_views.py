"""Bounded nonactivating rendering checks against source or installed content."""
import argparse
import datetime
import hashlib
import json
import subprocess

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import command_for, execute, verify_pack_native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("test", choices=["world_overview", "forest_horizon_world", "overview_terrain_coverage", "loading_progress_ui", "vehicle_parked_renderer", "vehicle_module_pack", "vegetation_removal_continuity", "vegetation_driving_profile", "vegetation_lod_world"])
    parser.add_argument("--pack", action="store_true")
    args = parser.parse_args()
    if args.pack and args.test == "loading_progress_ui":
        parser.error("Loading UI fixture writes source-only evidence; use its source check")
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/runtime_views" / stamp
    folder.mkdir(parents=True)
    command, cache = command_for(config.godot, args.test, folder, ["--view-output=" + folder.as_posix(), "--module-fixtures=" + (ROOT / "tests/fixtures").as_posix()])
    if args.test == "vegetation_driving_profile":
        command += ["--profile-dir=" + folder.as_posix(), "--profile-slot=recipe_generated_4644d8cfc8f97e43"]
    command.remove("--fullscreen")
    command[1:1] = ["--windowed", "--position", "-2400,-1600"]
    source = ROOT / "tests" / (args.test + ".gd")
    record = dict(command=command, cache=cache, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), **revision_metadata())
    if args.pack:
        record["native_sha256"] = verify_pack_native()
        driver = folder / "driver.gd"
        driver.write_bytes(source.read_bytes())
        if args.test == "vegetation_driving_profile":
            parent = ROOT / "tests/runtime_travel_profile.gd"
            staged_parent = folder / "travel_base.gd"
            staged_parent.write_bytes(parent.read_bytes())
            record["parent_source_sha256"] = hashlib.sha256(parent.read_bytes()).hexdigest()
            driver.write_text(source.read_text().replace("res://tests/runtime_travel_profile.gd", staged_parent.as_posix()), encoding="utf-8")
        command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        command[command.index("--path") + 1] = str(ROOT / "dist")
        command[command.index("--script") + 1] = str(driver)
        record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        marker = {"world_overview": "WORLD_OVERVIEW", "forest_horizon_world": "FOREST_HORIZON_WORLD failures=0", "overview_terrain_coverage": "OVERVIEW_TERRAIN_COVERAGE", "loading_progress_ui": "LOADING_PROGRESS_UI", "vehicle_module_pack": "VEHICLE_MODULE_PACK", "vehicle_parked_renderer": "VEHICLE_PARKED_RENDERER", "vegetation_removal_continuity": "failures=0", "vegetation_driving_profile": "TRAVEL_PROFILE PASS", "vegetation_lod_world": "VEGETATION_LOD_WORLD failures=0"}[args.test]
        record["result"] = execute(command, folder, 240, marker, require_resource_budget=True)
    finally:
        subprocess.Popen = original
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("PASS " if record["result"]["passed"] else "FAIL ") + str(folder))
    return 0 if record["result"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

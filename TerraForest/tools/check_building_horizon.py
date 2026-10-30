"""Nonactivating distant-building rendering and read-only populated-world checks."""
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
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--world", action="store_true")
    parser.add_argument("--slot", default="recipe_generated_4644d8cfc8f97e43")
    args = parser.parse_args()
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/building_horizon_checks" / stamp
    folder.mkdir(parents=True)
    test = "building_horizon_world" if args.world else "building_horizon"
    extra = ["--horizon-output=" + folder.as_posix(), "--horizon-slot=" + args.slot, "--horizon-images"]
    command, cache = command_for(config.godot, test, folder, extra)
    command.remove("--fullscreen")
    command[1:1] = ["--windowed", "--position", "-2400,-1600"]
    source = ROOT / "tests" / (test + ".gd")
    record = dict(command=command, cache=cache, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  native_sha256={str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                 for path in (ROOT / "addons").glob("*/bin/*.dll")}, **revision_metadata())
    if args.pack:
        verify_pack_native()
        driver = folder / "driver.gd"
        driver.write_bytes(source.read_bytes())
        command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        command[command.index("--path") + 1] = str(ROOT / "dist")
        command[command.index("--script") + 1] = str(driver)
        record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
    manifest = folder / "run.json"
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        record["result"] = execute(command, folder, 240, "BUILDING_HORIZON_WORLD" if args.world else "BUILDING_HORIZON", require_resource_budget=True)
    finally:
        subprocess.Popen = original
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("PASS " if record["result"]["passed"] else "FAIL ") + str(folder))
    return 0 if record["result"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

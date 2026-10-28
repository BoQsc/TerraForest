"""Verify generated lake crossings without activating or capturing the desktop."""
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
    parser.add_argument("--snapshot", default="")
    parser.add_argument("--metrics-only", action="store_true")
    options = parser.parse_args()
    settings, _ = parse_args([])
    native = verify_pack_native() if options.pack else {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((ROOT / "addons").glob("*/bin/*.dll"))
    }
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/checks" / (stamp + "_lake" + ("_pack" if options.pack else ""))
    folder.mkdir(parents=True)
    evidence = folder / "evidence/lake_crossing_world"
    evidence.mkdir(parents=True)
    extra = ["--lake-landscape", "--default-recipe"]
    if options.snapshot:
        extra.append("--lake-snapshot=" + options.snapshot)
    if options.metrics_only:
        extra.append("--city-metrics-only")
    command, cache = command_for(settings.godot, "lake_crossing_world", folder, extra)
    command.remove("--fullscreen")
    command[1:1] = ["--windowed", "--position", "-2400,-1600"]
    dependencies = {}
    names = ["window_session_flow", "world_recipe_generation", "approved_city_world", "lake_crossing_world"]
    for name in names:
        source = ROOT / "tests" / (name + ".gd")
        dependencies[str(source.relative_to(ROOT))] = hashlib.sha256(source.read_bytes()).hexdigest()
        script = source.read_text(encoding="utf-8").replace("res://reports", (folder / "evidence").as_posix())
        for dependency in names:
            script = script.replace('"res://tests/' + dependency + '.gd"', json.dumps((folder / (dependency + ".gd")).as_posix()))
        (folder / (name + ".gd")).write_text(script, encoding="utf-8")
    command[command.index("--script") + 1] = str(folder / "lake_crossing_world.gd")
    if options.pack:
        command[command.index("--path") + 1] = str(ROOT / "dist")
        command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
    record = dict(command=command, cache=cache, test_sha256=dependencies,
                  native_sha256=native, **revision_metadata())
    if options.pack:
        record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
    manifest = folder / "run.json"
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    original = subprocess.Popen

    def nonactivating(*args, **kwargs):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        kwargs["startupinfo"] = startup
        return original(*args, **kwargs)

    subprocess.Popen = nonactivating
    try:
        record["result"] = execute(command, folder, 600, "failures=0")
    finally:
        subprocess.Popen = original
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("PASS " if record["result"]["passed"] else "FAIL ") + str(folder))
    return 0 if record["result"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

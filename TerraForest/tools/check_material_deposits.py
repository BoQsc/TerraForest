"""Run mineral generation, persistence and gameplay checks without player-save edits."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import command_for, execute, verify_pack_native


CHECKS = {
    "material_deposits_native": (90, "MATERIAL_DEPOSITS_NATIVE checks=", True),
    "world_recipe_native": (90, "WORLD_RECIPE_NATIVE checks=", True),
    "material_deposits_plan": (100, "MATERIAL_DEPOSITS_PLAN checks=", True),
    "material_deposits_world": (180, "MATERIAL_DEPOSITS_WORLD checks=", False),
    "material_deposits_ui": (90, "MATERIAL_DEPOSITS_UI checks=", False),
    "world_recipe_generation": (600, "WORLD_RECIPE_GENERATION checks=", False),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--checks", nargs="+", choices=CHECKS, default=list(CHECKS))
    options = parser.parse_args()
    settings, _ = parse_args([])
    engine = Path(settings.godot).resolve()
    native = verify_pack_native() if options.pack else {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((ROOT / "addons").glob("*/bin/*.dll"))
    }
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/checks" / (stamp + "_minerals" + ("_pack" if options.pack else ""))
    folder.mkdir(parents=True)
    results = []
    for name in options.checks:
        output = folder / name
        output.mkdir()
        timeout, marker, headless = CHECKS[name]
        extra = []
        if name == "material_deposits_world":
            extra = ["--gameplay-construction", "--world-generator=23", "--world-seed=1703",
                     "--ground-cover", "--mineral-evidence=" + str(output / "evidence")]
        if name == "world_recipe_generation":
            extra = ["--default-recipe"]
        if name == "material_deposits_ui":
            extra = ["--mineral-evidence=" + str(output / "evidence")]
        command, cache = command_for(engine, name, output, extra, headless)
        source = ROOT / "tests" / (name + ".gd")
        dependencies = {str(source.relative_to(ROOT)): hashlib.sha256(source.read_bytes()).hexdigest()}
        if name == "world_recipe_generation":
            helper_source = ROOT / "tests/window_session_flow.gd"
            dependencies[str(helper_source.relative_to(ROOT))] = hashlib.sha256(helper_source.read_bytes()).hexdigest()
        if options.pack:
            driver = output / (name + "_external.gd")
            report_root = output / "evidence"
            report_root.mkdir(exist_ok=True)
            script = source.read_text(encoding="utf-8").replace("res://reports", report_root.as_posix())
            if name == "world_recipe_generation":
                helper = output / "window_session_base.gd"
                helper.write_text(helper_source.read_text(encoding="utf-8").replace("res://reports", report_root.as_posix()), encoding="utf-8")
                script = script.replace('"res://tests/window_session_flow.gd"', json.dumps(helper.as_posix()))
            driver.write_text(script, encoding="utf-8")
            command[command.index("--path") + 1] = str(ROOT / "dist")
            command[command.index("--script") + 1] = str(driver)
            command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        record = dict(test=name, command=command, utc=stamp, cache=cache,
                      native_sha256=native, test_sha256=dependencies, **revision_metadata())
        if options.pack:
            record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
            record["driver_sha256"] = hashlib.sha256(driver.read_bytes()).hexdigest()
        manifest = output / "run.json"
        manifest.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        record["result"] = execute(command, output, timeout, marker)
        manifest.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        results.append(dict(test=name, **record["result"]))
        print(("PASS " if record["result"]["passed"] else "FAIL ") + str(output), flush=True)
    (folder / "summary.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())

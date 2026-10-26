"""Retain source/package zombie checks, including known failing stress cases."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import command_for, execute, verify_pack_native


CHECKS = {
    "zombie_rest_support": (90, "ZOMBIE_REST_SUPPORT checks=", "--ragdoll-evidence="),
    "zombie_ragdoll_stress": (600, "ZOMBIE_RAGDOLL_STRESS failures=0", "--ragdoll-evidence="),
    "zombie_combat_regions": (120, "ZOMBIE_COMBAT_REGIONS checks=", "--zombie-combat-dir="),
    "zombie_ragdoll_reactivation": (150, "ZOMBIE_RAGDOLL_REACTIVATION failures=0", "--reactivation-evidence="),
    "zombie_anatomy": (60, "ZOMBIE_ANATOMY checks=", ""),
    "zombie_awareness": (60, "ZOMBIE_AWARENESS checks=", ""),
    "zombie_geometry_cache": (90, "ZOMBIE_GEOMETRY_CACHE checks=", ""),
    "zombie_behavior": (150, "ZOMBIE_BEHAVIOR checks=", "--zombie-behavior-dir="),
    "zombie_step_guard": (120, "ZOMBIE_STEP_GUARD PASS", ""),
    "zombie_slope_contract": (150, "ZOMBIE_SLOPE_CONTRACT failures=0", ""),
    "zombie_combat_world": (150, "ZOMBIE_COMBAT_WORLD checks=", "--zombie-world-evidence="),
}
STRESS_CASES = ["flat", "slope", "stairs", "rubble", "corner", "ledge", "pile", "severed", "far_origin", "ground_pile"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--graphical", action="store_true")
    parser.add_argument("--checks", nargs="+", choices=CHECKS,
                        default=[name for name in CHECKS if name != "zombie_combat_world"])
    parser.add_argument("--stress-hz", type=int, choices=[30, 60, 120], default=60)
    parser.add_argument("--stress-case", action="append", choices=STRESS_CASES, default=[])
    parser.add_argument("--forest", action="store_true")
    options = parser.parse_args()
    if "zombie_combat_world" in options.checks and not options.graphical:
        parser.error("zombie_combat_world requires --graphical")
    settings, _ = parse_args([])
    engine = Path(settings.godot).resolve()
    native = verify_pack_native() if options.pack else {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((ROOT / "addons").glob("*/bin/*.dll"))
    }
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/checks" / (stamp + "_zombies" + ("_pack" if options.pack else ""))
    folder.mkdir(parents=True)
    records = []
    for name in options.checks:
        output = folder / name
        output.mkdir()
        timeout, marker, evidence = CHECKS[name]
        extra = [evidence + str(output / "evidence")] if evidence else []
        if name == "zombie_ragdoll_stress":
            extra += [f"--stress-hz={options.stress_hz}"]
            extra += ["--stress-case=" + case for case in options.stress_case]
        if name == "zombie_ragdoll_reactivation" and options.forest:
            extra += ["--forest"]
        if name == "zombie_combat_world":
            extra += ["--gameplay-construction"]
        command, cache = command_for(engine, name, output, extra, not options.graphical)
        source = ROOT / "tests" / (name + ".gd")
        dependencies = {str(source.relative_to(ROOT)): hashlib.sha256(source.read_bytes()).hexdigest()}
        if name == "zombie_ragdoll_stress":
            base = ROOT / "tests/zombie_ragdoll_reactivation.gd"
            dependencies[str(base.relative_to(ROOT))] = hashlib.sha256(base.read_bytes()).hexdigest()
        if options.pack:
            driver = output / (name + "_external.gd")
            script = source.read_text(encoding="utf-8")
            report_root = output / "evidence"
            report_root.mkdir(exist_ok=True)
            script = script.replace("res://reports", report_root.as_posix())
            if name == "zombie_ragdoll_stress":
                helper = output / "reactivation_base.gd"
                helper.write_bytes((ROOT / "tests/zombie_ragdoll_reactivation.gd").read_bytes())
                script = script.replace('"res://tests/zombie_ragdoll_reactivation.gd"', json.dumps(helper.as_posix()))
            driver.write_text(script, encoding="utf-8")
            command[command.index("--path") + 1] = str(ROOT / "dist")
            command[command.index("--script") + 1] = str(driver)
            command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        record = dict(test=name, command=command, utc=stamp, cache=cache,
                      native_sha256=native, test_sha256=dependencies,
                      engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(), **revision_metadata())
        if options.pack:
            record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
            record["driver_sha256"] = hashlib.sha256(driver.read_bytes()).hexdigest()
        manifest = output / "run.json"
        manifest.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        record["result"] = execute(command, output, timeout, marker)
        manifest.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        records.append(dict(test=name, **record["result"]))
        print(("PASS " if record["result"]["passed"] else "FAIL ") + str(output), flush=True)
    (folder / "summary.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
    return 0 if all(record["passed"] for record in records) else 1


if __name__ == "__main__":
    raise SystemExit(main())

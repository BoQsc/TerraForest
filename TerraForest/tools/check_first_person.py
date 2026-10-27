"""Check first-person rendering against source or the exported pack using temporary worlds."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import command_for, execute, verify_pack_native


CHECKS = {
    "first_person_meshes": (90, "FIRST_PERSON_MESHES_CHECK checks=", True),
    "first_person_protection": (120, "FIRST_PERSON_PROTECTION checks=", False),
    "first_person_world": (180, "FIRST_PERSON_WORLD checks=", False),
    "attack_animation_timing": (60, "ATTACK_ANIMATION_TIMING checks=", True),
    "session_player_page": (120, "SESSION_PLAYER_PAGE checks=", False),
    "third_person_view": (140, "THIRD_PERSON_VIEW checks=", False),
    "pickaxe_fresh_world": (180, "PICKAXE_FRESH_WORLD checks=", False),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--checks", nargs="+", choices=CHECKS, default=list(CHECKS))
    options = parser.parse_args()
    settings, _ = parse_args([])
    native = verify_pack_native() if options.pack else {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((ROOT / "addons").glob("*/bin/*.dll"))
    }
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/checks" / (stamp + "_first_person" + ("_pack" if options.pack else ""))
    folder.mkdir(parents=True)
    results = []
    for name in options.checks:
        output = folder / name
        output.mkdir()
        timeout, marker, headless = CHECKS[name]
        extra = ["--gameplay-construction", "--world-generator=23", "--world-seed=1703", "--ground-cover",
                 "--viewmodel-evidence=" + str(output / "evidence"), "--third-person-evidence=" + str(output / "evidence"),
                 "--player-page-evidence=" + str(output / "evidence")]
        command, cache = command_for(Path(settings.godot).resolve(), name, output, extra, headless)
        source = ROOT / "tests" / (name + ".gd")
        dependencies = {str(source.relative_to(ROOT)): hashlib.sha256(source.read_bytes()).hexdigest()}
        script = source.read_text(encoding="utf-8").replace("res://reports", (output / "evidence").as_posix())
        if name == "pickaxe_fresh_world":
            base = ROOT / "tests/combined_resource_route.gd"
            dependencies[str(base.relative_to(ROOT))] = hashlib.sha256(base.read_bytes()).hexdigest()
            if options.pack:
                helper = output / "combined_resource_route.gd"
                helper.write_text(base.read_text(encoding="utf-8").replace("res://reports", (output / "evidence").as_posix()), encoding="utf-8")
                script = script.replace('"res://tests/combined_resource_route.gd"', json.dumps(helper.as_posix()))
        if options.pack:
            driver = output / (name + "_external.gd")
            driver.write_text(script, encoding="utf-8")
            command[command.index("--path") + 1] = str(ROOT / "dist")
            command[command.index("--script") + 1] = str(driver)
            command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        record = dict(test=name, command=command, utc=stamp, cache=cache, native_sha256=native,
                      test_sha256=dependencies, bake=json.loads((ROOT / "addons/characters/runtime/assets/first_person/bake.json").read_text()),
                      **revision_metadata())
        if options.pack:
            record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
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

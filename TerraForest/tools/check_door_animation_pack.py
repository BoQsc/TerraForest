# SPDX-License-Identifier: 0BSD
"""Check authored motion, ordinary E and mid-swing disk reload against the PCK."""
import datetime
import hashlib
import json
import uuid

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import command_for, execute, verify_pack_native


def main():
    engine = parse_args([])[0].godot
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/door_animation_pack" / stamp
    folder.mkdir(parents=True)
    native = verify_pack_native()
    drivers = {}
    # Assertion drivers live outside the pack; all gameplay and art resolve in it.
    for name in ("combined_resource_route", "terrain_storage_support", "door_animation", "door_world", "door_content_storage"):
        source = ROOT / "tests" / (name + ".gd")
        text = source.read_text(encoding="utf-8").replace("res://reports", folder.as_posix())
        for dependency in ("combined_resource_route", "terrain_storage_support"):
            text = text.replace("res://tests/" + dependency + ".gd", (folder / (dependency + ".gd")).as_posix())
        driver = folder / (name + ".gd")
        driver.write_text(text, encoding="utf-8")
        drivers[name] = dict(source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                             driver_sha256=hashlib.sha256(driver.read_bytes()).hexdigest())
    slot = "door_content_check_animation_pack_" + uuid.uuid4().hex
    records = []
    for label, test, headless, extra, marker in (
        ("motion", "door_animation", True, [], "DOOR_ANIMATION checks=26 failures=0"),
        ("world", "door_world", False, [], "COMBINED_RESOURCE_ROUTE failures=0"),
        ("save", "door_content_storage", True, ["--door-content-slot=" + slot, "--animate-doors"], "DOOR_CONTENT_STORAGE phase=create failures=0"),
        ("reopen", "door_content_storage", True, ["--door-content-slot=" + slot, "--animate-doors", "--reopen-doors"], "DOOR_CONTENT_STORAGE phase=reopen failures=0"),
    ):
        output = folder / label
        output.mkdir()
        command, cache = command_for(engine, test, output, extra, headless=headless)
        command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        command[command.index("--path") + 1] = str(ROOT / "dist")
        command[command.index("--script") + 1] = str(folder / (test + ".gd"))
        result = execute(command, output, 150, marker)
        records.append(dict(test=label, command=command, cache=cache, **result))
        print(("PASS " if result["passed"] else "FAIL ") + label, flush=True)
        if not result["passed"]:
            break
    passed = len(records) == 4 and all(row["passed"] for row in records)
    record = dict(passed=passed, tests=records, drivers=drivers, native_sha256=native,
                  pack_sha256=hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest(),
                  **revision_metadata())
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("PASS " if passed else "FAIL ") + str(folder))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

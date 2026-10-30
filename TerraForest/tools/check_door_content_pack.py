# SPDX-License-Identifier: 0BSD
"""Check packed door definitions and runtime loose-GLB import with matching DLLs."""
import datetime
import hashlib
import json

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import command_for, execute, verify_pack_native


def main():
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/door_content_pack" / stamp
    folder.mkdir(parents=True)
    native = verify_pack_native()
    source = ROOT / "tests/door_content.gd"
    driver = folder / "driver.gd"
    # Test scripts/old binary fixtures are intentionally excluded from the game.
    # All addon code, definitions and the example pack must resolve from the PCK.
    driver.write_text(source.read_text(encoding="utf-8").replace(
        "res://tests/fixtures/door_legacy/",
        (ROOT / "tests/fixtures/door_legacy").as_posix() + "/").replace(
        "res://reports", folder.as_posix()), encoding="utf-8")
    command, cache = command_for(config.godot, "door_content", folder, [], headless=True)
    command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
    command[command.index("--path") + 1] = str(ROOT / "dist")
    command[command.index("--script") + 1] = str(driver)
    record = dict(command=command, cache=cache, native_sha256=native,
                  source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  driver_sha256=hashlib.sha256(driver.read_bytes()).hexdigest(),
                  pack_sha256=hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest(),
                  **revision_metadata())
    record["result"] = execute(command, folder, 60, "DOOR_CONTENT checks=58 failures=0")
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("PASS " if record["result"]["passed"] else "FAIL ") + str(folder))
    return 0 if record["result"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

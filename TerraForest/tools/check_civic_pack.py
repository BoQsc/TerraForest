# SPDX-License-Identifier: 0BSD
"""Verify civic candidates, currency and trader dependencies from the exported PCK."""
import datetime
import hashlib
import json

from run import ROOT, parse_args
from run_godot_check import command_for, execute, revision_metadata, verify_pack_native


def main():
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/civic_pack" / stamp
    folder.mkdir(parents=True)
    native = verify_pack_native()
    source = ROOT / "tests/civic_pack.gd"
    driver = folder / "driver.gd"
    driver.write_bytes(source.read_bytes())
    command, cache = command_for(config.godot, "civic_pack", folder, [], headless=True)
    command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
    command[command.index("--path") + 1] = str(ROOT / "dist")
    command[command.index("--script") + 1] = str(driver)
    record = dict(command=command, cache=cache, native_sha256=native,
                  test_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  pack_sha256=hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest(),
                  **revision_metadata())
    record["result"] = execute(command, folder, 60, "CIVIC_PACK failures=0")
    (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(("PASS " if record["result"]["passed"] else "FAIL ") + str(folder))
    return 0 if record["result"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

# SPDX-License-Identifier: 0BSD
"""Verify the frozen installed package, even while its source checkout changes."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path

import run_godot_check as checks
from run import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.project.resolve()
    checks.ROOT = root
    native = checks.verify_pack_native(root)
    pack = root / "dist/TerraForest.pck"
    engine = root / "TerraForest.exe"
    if not engine.is_file():
        parser.error("Installed TerraForest.exe is required")
    pack_hash = hashlib.sha256(pack.read_bytes()).hexdigest()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = root / "reports/entry_fly_in_pack" / stamp
    folder.mkdir(parents=True)
    source = ROOT / "tests/entry_fly_in.gd"
    driver = folder / source.name
    driver.write_bytes(source.read_bytes())
    records = []
    for label, extra in (("browser", ["--entry-browser"]),
                         ("populated", ["--entry-slot=Exploration_1703_8f8d4c8f", "--entry-video"])):
        output = folder / label
        output.mkdir()
        command, cache = checks.command_for(engine, "entry_fly_in", output,
                                           [*extra, "--entry-output=" + output.as_posix()])
        command[1:1] = ["--main-pack", str(pack)]
        command[command.index("--path") + 1] = str(root / "dist")
        command[command.index("--script") + 1] = str(driver)
        result = checks.execute(command, output, 180, "failures=0")
        records.append(dict(test=label, command=command, cache=cache, **result))
        print(("PASS " if result["passed"] else "FAIL ") + label, flush=True)
        if not result["passed"]:
            break
    passed = len(records) == 2 and all(row["passed"] for row in records)
    passed = passed and hashlib.sha256(pack.read_bytes()).hexdigest() == pack_hash
    record = dict(passed=passed, tests=records, pack_sha256=pack_hash, native_sha256=native,
                  engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(),
                  test_sha256=hashlib.sha256(driver.read_bytes()).hexdigest())
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("PASS " if passed else "FAIL ") + str(folder), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

# SPDX-License-Identifier: 0BSD
"""Verify the frozen installed package, even while its source checkout changes."""
import argparse
import datetime
import hashlib
import json
import subprocess
from pathlib import Path

import run_godot_check as checks
from run import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--source", action="store_true", help="Check current source before exporting")
    parser.add_argument("--wake-slot", help="Read-only upstairs introduction fixture")
    parser.add_argument("--case", choices=["browser", "populated", "upstairs"])
    args = parser.parse_args()
    root = args.project.resolve()
    checks.ROOT = root
    native = checks.verify_pack_native(root) if not args.source else {}
    pack = root / "dist/TerraForest.pck"
    engine = Path(checks.parse_args([])[0].godot) if args.source else root / "TerraForest.exe"
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
    cases = [("browser", ["--entry-browser"]),
             ("populated", ["--entry-slot=Exploration_1703_8f8d4c8f", "--entry-video"])]
    if args.wake_slot:
        cases.append(("upstairs", ["--entry-slot=" + args.wake_slot, "--entry-wakeup"]))
    if args.case:
        cases = [case for case in cases if case[0] == args.case]
        if not cases:
            parser.error("The upstairs case requires --wake-slot")
    for label, extra in cases:
        output = folder / label
        output.mkdir()
        command, cache = checks.command_for(engine, "entry_fly_in", output,
                                           [*extra, "--entry-output=" + output.as_posix()])
        if not args.source:
            command[1:1] = ["--main-pack", str(pack)]
            command[command.index("--path") + 1] = str(root / "dist")
        command[command.index("--script") + 1] = str(driver)
        command[command.index("--fullscreen")] = "--windowed"
        command[1:1] = ["--position", "-2400,-1600"]
        original = subprocess.Popen

        def nonactivating(*arguments, **keywords):
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = 4
            keywords["startupinfo"] = startup
            return original(*arguments, **keywords)

        subprocess.Popen = nonactivating
        try:
            result = checks.execute(command, output, 180, "failures=0")
        finally:
            subprocess.Popen = original
        records.append(dict(test=label, command=command, cache=cache, **result))
        print(("PASS " if result["passed"] else "FAIL ") + label, flush=True)
        if not result["passed"]:
            break
    passed = len(records) == len(cases) and all(row["passed"] for row in records)
    passed = passed and hashlib.sha256(pack.read_bytes()).hexdigest() == pack_hash
    record = dict(passed=passed, source=args.source, tests=records, pack_sha256=pack_hash, native_sha256=native,
                  engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(),
                  test_sha256=hashlib.sha256(driver.read_bytes()).hexdigest())
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("PASS " if passed else "FAIL ") + str(folder), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

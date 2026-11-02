# SPDX-License-Identifier: 0BSD
"""Verify production door dimensions and capture their actual rendered geometry."""
import argparse
import datetime
import json
import subprocess
from pathlib import Path
import run_godot_check as checks
from run import ROOT, parse_args


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="store_true")
    args = parser.parse_args()
    engine = ROOT / "TerraForest.exe" if args.pack else Path(parse_args([])[0].godot)
    native = checks.verify_pack_native() if args.pack else {}
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/door_dimensions" / stamp
    folder.mkdir(parents=True)
    driver = folder / "door_dimensions.gd"
    driver.write_bytes((ROOT / "tests/door_dimensions.gd").read_bytes())
    results = []
    variants = [("corrected", ["--door-photo"])]
    if not args.pack:
        baseline = subprocess.check_output(["git", "show", "0740b507001725b2e25fbaab1913571db55685c9:TerraForest/addons/structures/prefabs/expansion_church_c1_e2.tres"], cwd=ROOT)
        (ROOT / "reports/door_dimensions/original_church.tres").write_bytes(baseline)
        variants.insert(0, ("baseline", ["--door-photo", "--door-baseline"]))
    for label, extra in variants:
        output = folder / label
        output.mkdir()
        command, _ = checks.command_for(engine, "door_dimensions", output, [*extra, "--door-output=" + output.as_posix()])
        command[command.index("--fullscreen")] = "--windowed"
        command[1:1] = ["--position", "-2400,-1600"]
        if args.pack:
            command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
            command[command.index("--path") + 1] = str(ROOT / "dist")
            command[command.index("--script") + 1] = str(driver)
        original = subprocess.Popen
        def nonactivating(*arguments, **keywords):
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = 4
            keywords["startupinfo"] = startup
            return original(*arguments, **keywords)
        subprocess.Popen = nonactivating
        try:
            result = checks.execute(command, output, 90, "failures=0")
        finally:
            subprocess.Popen = original
        results.append(dict(label=label, **result))
        print(("PASS " if result["passed"] else "FAIL ") + label, flush=True)
    passed = all(row["passed"] for row in results)
    (folder / "run.json").write_text(json.dumps(dict(passed=passed, pack=args.pack, native=native, results=results), indent=2))
    print(("PASS " if passed else "FAIL ") + str(folder), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

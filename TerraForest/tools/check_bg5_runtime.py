# SPDX-License-Identifier: 0BSD
"""Verify BG5 resources from source/PCK, or capture a noncapturing native preview."""
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
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    engine = parse_args([])[0].godot
    test = "bg5_preview" if args.preview else "bg5_runtime"
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/bg5_runtime" / stamp
    folder.mkdir(parents=True)
    extra = ["--view-output=" + folder.as_posix(),
             "--door-fixtures=" + (ROOT / "tests/fixtures/door_legacy").as_posix() + "/"]
    command, cache = command_for(engine, test, folder, extra, headless=not args.preview)
    if args.preview:
        command.remove("--fullscreen")
        command[command.index("--resolution")+1] = "1600x1000"
        command[1:1] = ["--windowed", "--position", "-2400,-1600"]
    source = ROOT / "tests" / (test + ".gd")
    record = dict(command=command, cache=cache,
                  source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), **revision_metadata())
    if args.pack:
        command.append("--packed-bg5-check")
        record["native_sha256"] = verify_pack_native()
        driver = folder / "driver.gd"
        driver.write_bytes(source.read_bytes())
        command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        command[command.index("--path")+1] = str(ROOT / "dist")
        command[command.index("--script")+1] = str(driver)
        record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
    original = subprocess.Popen
    def nonactivating(*positional, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*positional, **keywords)
    subprocess.Popen = nonactivating
    try:
        record["result"] = execute(command, folder, 60, "failures=0", require_resource_budget=args.preview)
    finally:
        subprocess.Popen = original
    (folder / "run.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("PASS " if record["result"]["passed"] else "FAIL ") + str(folder))
    return 0 if record["result"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

# SPDX-License-Identifier: 0BSD
"""Run gathering/corpse interactions and fresh-process reopen in an owned save slot."""
import datetime
import hashlib
import json
import uuid
import argparse
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import command_for, execute
from play_checkpoint import revision_metadata

options = argparse.ArgumentParser(description=__doc__)
options.add_argument("--pack", action="store_true")
options = options.parse_args()
args, extra = parse_args([])
token = uuid.uuid4().hex
slot = "gather_lifecycle_" + token[:24]
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
folder = ROOT / "reports/checks" / (stamp + "_gathering_lifecycle" + ("_pack" if options.pack else ""))
for phase in ["build", "reopen"]:
    output = folder / phase
    output.mkdir(parents=True)
    command, cache = command_for(args.godot, "gathering_lifecycle", output,
        ["--gameplay-construction", "--ground-cover", "--gather-evidence=" + str(output / "captures")])
    command = [a for a in command if a != "--temporary"]
    command = ["--world-slot="+slot if a.startswith("--world-slot=") else a for a in command]
    if phase == "reopen":command += ["--reopen-loop", "--snapshot-readonly"]
    if options.pack:
        driver=output / "gathering_lifecycle_external.gd"
        driver.write_bytes((ROOT / "tests/gathering_lifecycle.gd").read_bytes())
        command[command.index("--path")+1]=str(ROOT / "dist")
        command[command.index("--script")+1]=str(driver)
        command[1:1]=["--main-pack",str(ROOT / "dist/TerraForest.pck")]
    record = dict(command=command, utc=stamp, slot=slot, phase=phase,
        engine_sha256=hashlib.sha256(Path(args.godot).read_bytes()).hexdigest(),
        test_sha256=hashlib.sha256((ROOT / "tests/gathering_lifecycle.gd").read_bytes()).hexdigest(),
        native_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/"addons").glob("*/bin/*.dll"))}, **revision_metadata())
    if options.pack:record["pack_sha256"]=hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
    manifest = output / "run.json"
    manifest.write_text(json.dumps(record, indent=2)+"\n", encoding="utf-8")
    record["result"] = execute(command, output, 110, "failures=0 reopen=")
    manifest.write_text(json.dumps(record, indent=2)+"\n", encoding="utf-8")
    print(("PASS " if record["result"]["passed"] else "FAIL ")+str(output), flush=True)
    if not record["result"]["passed"]:raise SystemExit(1)

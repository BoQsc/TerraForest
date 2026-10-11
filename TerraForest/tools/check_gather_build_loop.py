# SPDX-License-Identifier: 0BSD
"""Fresh-slot main-world gather/craft/build/save and separate-process reopen check."""
import datetime
import hashlib
import json
import uuid
from pathlib import Path
from run import ROOT, parse_args
from run_godot_check import command_for, execute
from play_checkpoint import revision_metadata

def main():
    args, extra = parse_args()
    if extra:
        raise SystemExit("No extra world arguments supported by this isolated check")
    token = uuid.uuid4().hex
    slot = "gather_loop_" + token
    cache = "user://gather_loop_" + token
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/gather_build_loop" / stamp
    for phase in ["build", "reopen"]:
        output = folder / phase
        output.mkdir(parents=True)
        command, _ = command_for(args.godot, "gather_build_loop", output,
                                 ["--ground-cover", "--gameplay-construction"])
        command = [arg for arg in command if arg != "--temporary"]
        command = ["--world-slot=" + slot if arg.startswith("--world-slot=") else
                   "--derived-cache=" + cache if arg.startswith("--derived-cache=") else arg
                   for arg in command]
        if phase == "reopen":
            command.append("--reopen-loop")
        record = dict(command=command, phase=phase, slot=slot, cache=cache,
                      engine_sha256=hashlib.sha256(Path(args.godot).read_bytes()).hexdigest(),
                      test_sha256=hashlib.sha256((ROOT/"tests/gather_build_loop.gd").read_bytes()).hexdigest(),
                      native_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in sorted((ROOT/"addons").glob("*/bin/*.dll"))},
                      **revision_metadata())
        manifest = output / "run.json"
        manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
        record["result"] = execute(command, output, 110, "GATHER_BUILD_LOOP ")
        manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
        print(("PASS " if record["result"]["passed"] else "FAIL ") + str(output), flush=True)
        if not record["result"]["passed"]:
            return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

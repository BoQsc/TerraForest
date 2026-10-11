# SPDX-License-Identifier: 0BSD
"""Run navigation/save checks on a unique copy of the authored furnished world."""
import datetime
import hashlib
import json
import os
from pathlib import Path
from clone_world import clone_once
from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
source = json.loads((ROOT / "docs/evidence/generated_furnished/manifest.json").read_text())
slot = "actor_settlement_" + stamp
worlds = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds"
copy = clone_once(worlds, source["slot"], slot)
folder = ROOT / "reports/checks" / stamp
folder.mkdir(parents=True)
config, _ = parse_args([])
command = [config.godot, "--path", str(ROOT), "--fullscreen", "--resolution", "1920x1080", "--max-fps", "60", "--log-file", str(folder / "engine.log"), "--script", "res://tests/actor_settlement_navigation.gd", "--", "--world-slot="+slot, "--actors", "--ground-cover", "--derived-cache=user://"+slot]
metadata = dict(command=command, copy=copy, **revision_metadata())
metadata["native_sha256"] = {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/"addons").glob("*/bin/*.dll")}
metadata["test_sha256"] = hashlib.sha256((ROOT/"tests/actor_settlement_navigation.gd").read_bytes()).hexdigest()
metadata.update(execute(command, folder, 90, "ACTOR_SETTLEMENT_NAVIGATION failures=0"))
metadata["source_unchanged"] = hashlib.sha256((worlds/(source["slot"]+".trw")).read_bytes()).hexdigest()==copy["source_sha256"]
(folder/"run.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
print(("PASS " if metadata["passed"] and metadata["source_unchanged"] else "FAIL ")+str(folder))
raise SystemExit(0 if metadata["passed"] and metadata["source_unchanged"] else 1)

# SPDX-License-Identifier: 0BSD
"""Verify zombie combat and physical anatomy against the exported game."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import sys

root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(root / "tools"))
from run import parse_args
from run_godot_check import command_for, execute
from play_checkpoint import revision_metadata

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--regions", action="store_true", help="Run all animated regions and physical sever roots instead of player weapon combat")
args = parser.parse_args()
test = "zombie_combat_regions" if args.regions else "zombie_combat_world"
expected = "ZOMBIE_COMBAT_REGIONS checks=39 failures=0" if args.regions else "ZOMBIE_COMBAT_WORLD checks=26 failures=0"
config, _ = parse_args([])
engine = Path(config.godot).resolve()
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
folder = root / "reports/checks" / (stamp + "_" + test + "_pack")
folder.mkdir(parents=True)
pack = root / "dist/TerraForest.pck"
external = folder / (test + "_external.gd")
external.write_bytes((root / "tests" / (test + ".gd")).read_bytes())
evidence_flag = "--zombie-combat-dir=" if args.regions else "--zombie-world-evidence="
command, cache = command_for(engine, test, folder, ["--gameplay-construction", "--zombies", evidence_flag + str(folder / "captures")])
command[command.index("--path") + 1] = str(root / "dist")
command[command.index("--script") + 1] = str(external)
command[1:1] = ["--main-pack", str(pack)]
details = dict(command=command, cache=cache, utc=stamp,
               scope="Exported PCK/dist runtime; actual player weapon contact, health, severing and forest corpse rest." if not args.regions else "Exported PCK/dist runtime; real animated rig regions, all sever roots and physical rest/wake.",
               engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(),
               pack_sha256=hashlib.sha256(pack.read_bytes()).hexdigest(),
               test_sha256=hashlib.sha256(external.read_bytes()).hexdigest(),
               native_sha256={str(p.relative_to(root / "dist")): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((root / "dist/addons").glob("*/bin/*.dll"))}, **revision_metadata())
manifest = folder / "run.json"
manifest.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")
details["result"] = execute(command, folder, 100, expected)
manifest.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")
print(("PASS " if details["result"]["passed"] else "FAIL ") + str(folder), flush=True)
raise SystemExit(0 if details["result"]["passed"] else 1)

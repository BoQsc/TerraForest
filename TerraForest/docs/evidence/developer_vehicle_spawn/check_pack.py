# SPDX-License-Identifier: 0BSD
"""Run the actual ESC vehicle-spawn action against PCK/dist resources."""
from pathlib import Path
import datetime
import hashlib
import json
import sys

root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(root / "tools"))
from run import parse_args
from run_godot_check import command_for, execute
from play_checkpoint import revision_metadata

config, _ = parse_args([])
engine = Path(config.godot).resolve()
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
folder = root / "reports/checks" / (stamp + "_developer_vehicle_spawn_pack")
folder.mkdir(parents=True)
pack = root / "dist/TerraForest.pck"
driver = folder / "developer_vehicle_spawn_external.gd"
driver.write_bytes((root / "tests/developer_vehicle_spawn.gd").read_bytes())
command, cache = command_for(engine, "developer_vehicle_spawn", folder, ["--gameplay-construction", "--vehicle-fleet", "--no-zombies", "--vehicle-spawn-evidence=" + str(folder / "captures")])
command[command.index("--path") + 1] = str(root / "dist")
command[command.index("--script") + 1] = str(driver)
command[1:1] = ["--main-pack", str(pack)]
details = dict(command=command, cache=cache, utc=stamp,
               scope="First Developer-menu click from gameplay, sky aim, ordinary placement unavailable; immediate visible frozen body with no mode switch. Game resources resolve from PCK/dist.",
               engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(),
               pack_sha256=hashlib.sha256(pack.read_bytes()).hexdigest(),
               test_sha256=hashlib.sha256(driver.read_bytes()).hexdigest(),
               native_sha256={str(p.relative_to(root / "dist")): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((root / "dist/addons").glob("*/bin/*.dll"))}, **revision_metadata())
manifest = folder / "run.json"
manifest.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")
details["result"] = execute(command, folder, 100, "DEVELOPER_VEHICLE_SPAWN checks=7 failures=0")
manifest.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")
print(("PASS " if details["result"]["passed"] else "FAIL ") + str(folder), flush=True)
raise SystemExit(0 if details["result"]["passed"] else 1)

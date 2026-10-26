"""Verify animated mining and visible excavation on an isolated saved-world copy."""
import argparse
import hashlib
import json
import os
import re
import uuid
from pathlib import Path

from clone_world import clone_once
from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata, verify_pack_native


def source_hashes(worlds, slot):
    root = worlds / (slot + ".trw")
    paths = [root]
    for suffix in (".regions", ".models", ".water", ".terrain"):
        paths.extend(path for path in root.with_name(root.name + suffix).rglob("*") if path.is_file())
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slot", required=True)
    parser.add_argument("--godot")
    parser.add_argument("--pack", action="store_true")
    args = parser.parse_args()
    config, _ = parse_args(["--godot", args.godot] if args.godot else [])
    native = verify_pack_native() if args.pack else None
    token = uuid.uuid4().hex
    slot = "mining_target_" + token
    folder = ROOT / "reports/mining_target" / token
    folder.mkdir(parents=True)
    worlds = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds"
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,47}", args.slot):
        parser.error("Use a saved world slot name, not a path")
    before = source_hashes(worlds, args.slot)
    copied = clone_once(worlds, args.slot, slot)
    record = {**revision_metadata(), "copy": copied, "source_hashes": before,
              "matching_pack_native": native, "runs": [],
              "native_sha256": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                for path in sorted((ROOT / "addons").glob("*/bin/*.dll"))},
              "scope": "Three animated graphical pickaxe strikes and three offscreen graphical contacts at a saved pose; not a broad performance qualification."}
    for phase in ("animated", "graphical"):
        output = folder / phase
        output.mkdir()
        command = [str(config.godot), "--path", str(ROOT), "--log-file", str(output / "engine.log"),
                   *( ["--windowed", "--resolution", "1280x720"] if phase == "animated" else ["--minimized"] ), "--max-fps", "60"]
        if args.pack:
            command += ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        command += ["--script", "res://tests/mining_saved_target.gd", "--", "--temporary", "--snapshot-readonly",
                    "--world-slot=" + slot, "--derived-cache=user://" + slot, "--ground-cover", "--actors",
                    "--vehicle-fleet", "--gameplay-construction", "--mining-evidence=" + str(output)]
        if phase == "animated":
            command.append("--mining-input")
        result = execute(command, output, 150, "MINING_SAVED_TARGET failures=0")
        record["runs"].append({"phase": phase, "command": command, "result": result})
        record["source_unchanged"] = before == source_hashes(worlds, args.slot)
        (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        print(("PASS " if result["passed"] else "FAIL ") + phase, flush=True)
        if not record["source_unchanged"]:
            raise RuntimeError("Source save changed during inspection; evidence cannot establish a stable source")
    passed = all(row["result"]["passed"] for row in record["runs"])
    print(str(folder / "run.json"), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

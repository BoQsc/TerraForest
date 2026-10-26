"""Measure held mining after travel using isolated worlds or read-only save copies."""
import argparse
import hashlib
import json
import os
import shutil
import time
import uuid
from pathlib import Path

from run import ROOT, parse_args
from run_godot_check import command_for, execute, revision_metadata


def fingerprints(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--slot")
    parser.add_argument("--seed", type=int, default=1703)
    parser.add_argument("--repeat", type=int, choices=range(1, 6), default=1)
    parser.add_argument("--whole-patch", action="store_true")
    parser.add_argument("--coarse-arrival", action="store_true", help="Wait for the distant coarse parent before travel, never for fine target readiness")
    parser.add_argument("--visual", action="store_true")
    args = parser.parse_args()
    if args.slot and not args.slot.isidentifier():
        parser.error("Slot must be an identifier")
    config, _ = parse_args([])
    token = uuid.uuid4().hex[:16]
    folder = ROOT / "reports/mining_locality" / token
    folder.mkdir(parents=True)
    entries, source_files = [], []
    worlds = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds"
    if args.slot:
        source = worlds / (args.slot + ".trw")
        if not source.is_file():
            parser.error("Saved world not found")
        entries = [entry for entry in [source, *worlds.glob(args.slot + ".trw.*")]
                   if entry.suffix not in (".bak", ".lock")]
        for entry in entries:
            source_files.extend(path for path in entry.rglob("*") if path.is_file() and path.suffix != ".lock") if entry.is_dir() else source_files.append(entry)
    before = fingerprints(source_files)
    resource_root = ROOT / "dist" if args.pack else ROOT
    pack = resource_root / "TerraForest.pck"
    manifest = {**revision_metadata(), "arguments": vars(args), "source_files": before,
                "engine_sha256": hashlib.sha256(Path(config.godot).read_bytes()).hexdigest(),
                "pack_sha256": hashlib.sha256(pack.read_bytes()).hexdigest() if args.pack else None,
                "native_sha256": fingerprints(sorted((resource_root / "addons/volumetric_terrain/bin").glob("*.dll"))),
                "test_sha256": fingerprints([ROOT / "tests/held_mining_flight.gd", ROOT / "tests/foundation_mining.gd"]),
                "runs": [], "scope": "Two real-held-input arrivals per run; fresh cache. Optional save copies never modify the source. Visual readback is not performance acceptance."}
    for iteration in range(args.repeat):
        destination = folder / str(iteration)
        destination.mkdir()
        extra = ["--ground-cover", "--no-zombies"]
        if not args.slot:
            extra += ["--world-generator=23", "--world-seed=" + str(args.seed)]
        if args.whole_patch:
            extra.append("--whole-patch-terrain")
        if args.coarse_arrival:
            extra.append("--coarse-arrival")
        if args.visual:
            extra.append("--visual-debug")
        command, cache = command_for(Path(config.godot), "held_mining_flight", destination, extra)
        if args.slot:
            copied_slot = "mining_arrival_" + token + "_" + str(iteration)
            for entry in entries:
                copy = worlds / (copied_slot + entry.name[len(args.slot):])
                if copy.exists():
                    raise RuntimeError("Diagnostic copy already exists")
                shutil.copytree(entry, copy, ignore=shutil.ignore_patterns("*.lock")) if entry.is_dir() else shutil.copy2(entry, copy)
            if before != fingerprints(source_files):
                raise RuntimeError("Source save changed during copying; no diagnostic launched")
            command = ["--world-slot=" + copied_slot if value.startswith("--world-slot=") else value for value in command]
            command.append("--snapshot-readonly")
        if args.pack:
            command[1:1] = ["--main-pack", str(pack)]
        started = time.time()
        result = execute(command, destination, 180, "bounded observer writer retains all frames and progress reports")
        unchanged = before == fingerprints(source_files)
        for name in ["held_mining_flight.json", "foundation_mining.frames.csv"]:
            source = ROOT / "reports" / name
            if source.is_file() and source.stat().st_mtime >= started:
                shutil.copy2(source, destination / name)
        trace = ROOT / "reports/mining_visual/trace.json"
        if args.visual and trace.is_file() and trace.stat().st_mtime >= started:
            shutil.copytree(ROOT / "reports/mining_visual", destination / "visual", ignore=shutil.ignore_patterns("*.import", "*.translation"))
        manifest["runs"].append({"command": command, "cache": cache, "result": result, "source_unchanged": unchanged})
        (folder / "run.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(("PASS " if result["passed"] and unchanged else "FAIL ") + str(destination), flush=True)
        if not unchanged:
            break
    return 0 if all(row["result"]["passed"] and row["source_unchanged"] for row in manifest["runs"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())

"""Isolated terrain editing regression matrix; never selects a player's save."""
import argparse
import datetime
import hashlib
import json
import shutil
import time
from pathlib import Path

from run import ROOT, parse_args
from run_godot_check import command_for, execute, revision_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--native-only", action="store_true")
    parser.add_argument("--pack", action="store_true", help="Exercise exported resources with external test scripts")
    parser.add_argument("--case", action="append", help="Run only named cases; repeat to select several")
    parser.add_argument("--extended", action="store_true", help="4,800 rendered mixed edits instead of 1,200")
    parser.add_argument("--with-known-continuity-check", action="store_true", help="Also run the unresolved post-flight 150ms mining continuity gate")
    args = parser.parse_args()
    config, _ = parse_args(["--godot", args.godot] if args.godot else [])
    engine = Path(config.godot).resolve()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    folder = ROOT / "reports" / "terrain_editing" / stamp
    folder.mkdir(parents=True)
    headless = [
        ("ground_cover_retirement", "GROUND_COVER_RETIREMENT failures=0"),
        ("terrain_edit_recovery", "TERRAIN_EDIT_RECOVERY failures=0"),
        ("terrain_edit_paged_recovery", "TERRAIN_EDIT_PAGED_RECOVERY failures=0"),
        ("terrain_edit_volumes", "TERRAIN_EDIT_VOLUMES failures=0"),
        ("terrain_storage_failure", "TERRAIN_STORAGE_FAILURE failures=0"),
        ("terrain_history_storage", "TERRAIN_HISTORY_STORAGE failures=0"),
        ("terrain_residency", "TERRAIN_RESIDENCY failures=0"),
        ("terrain_residency_capacity", "TERRAIN_RESIDENCY_CAPACITY failures=0"),
        ("terrain_material_items", "TERRAIN_MATERIAL_ITEMS failures=0"),
        ("mining_rewards", "MINING_REWARDS"),
        ("terrain_density_backend_probe", "shutdown accounts for all accepted queries"),
        ("terrain_target_readiness_probe", "TARGET_READINESS"),
        ("terrain_graded_bed", "public grading API rejects invalid material"),
        ("terrain_road_bed", "legacy 36-byte road command remains accepted"),
        ("site_preparation", "rejected edit is not mistaken for successful no-op"),
        ("site_preparation_noop", "entire already prepared site completes without changing terrain"),
        ("terrain_lot_preparation", "failures=0"),
        ("terrain_preparation_priority", "background resumes without rebuilding completed pieces"),
        ("road_editor_settings", "invalid encoding rejected"),
        ("water_static_editing", "WATER_STATIC_EDITING failures=0"),
    ]
    cases = [(name, marker, True, []) for name, marker in headless]
    if not args.native_only:
        water = ["--water-gameplay", "--water-bucket-review", "--gameplay-construction", "--no-zombies"]
        cases += [
            ("developer_belt", "DEVELOPER_BELT", False, []),
            ("terrain_placement_preview", "TERRAIN_PLACEMENT_PREVIEW", False, ["--gameplay-construction"]),
            ("road_editor", "editor road completes without worker error", False, []),
            ("smooth_road_editor", "editor construction publishes terrain changes", False, []),
            ("vegetation_steep_mining", "VEGETATION_STEEP_MINING", False, ["--world-generator=21", "--world-seed=1703", "--ground-cover"]),
            ("vegetation_edit_continuity", "VEGETATION_EDIT_CONTINUITY", False, []),
        ]
        for name in ["water_editor_actions", "water_edit_cancellation", "water_static_mining", "water_mining_topology"]:
            cases.append((name, name.upper() + " failures=0", False, water))
        cases.append(("terrain_tools_endurance", "TERRAIN_TOOLS_ENDURANCE failures=0", False,
                      ["--world-generator=23", "--ground-cover", "--no-zombies", "--terrain-soak-rounds=" + ("12" if args.extended else "3")]))
        if args.with_known_continuity_check:
            cases.append(("held_mining_flight", "bounded observer writer retains all frames and progress reports", False, []))
    if args.case:
        unknown = set(args.case) - {case[0] for case in cases}
        if unknown:
            parser.error("Unavailable cases: " + ", ".join(sorted(unknown)))
        cases = [case for case in cases if case[0] in args.case]
    resource_root = ROOT / "dist" if args.pack else ROOT
    pack = resource_root / "TerraForest.pck"
    if args.pack and not pack.is_file():
        parser.error("Export the resource pack first")
    manifest = {**revision_metadata(), "engine": str(engine), "engine_sha256": hashlib.sha256(engine.read_bytes()).hexdigest(),
                "native_sha256": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                  for path in sorted((resource_root / "addons/volumetric_terrain/bin").glob("*.dll"))},
                "pack_sha256": hashlib.sha256(pack.read_bytes()).hexdigest() if args.pack else None,
                "scope": "Finite isolated cases, not exhaustive or multi-hour qualification. External test scripts; graphical captures require separate inspection.",
                "known_open_gate": "held_mining_flight: post-flight visible-change gaps can exceed 150ms", "runs": []}
    for name, marker, headless_mode, extra in cases:
        destination = folder / name
        destination.mkdir()
        command, cache = command_for(engine, name, destination, extra, headless_mode)
        if name == "terrain_placement_preview":
            command.append("--preview-evidence=" + str(ROOT / "reports/terrain_placement_preview"))
        if name == "developer_belt":
            command.append("--tool-ui-captures=" + str(ROOT / "reports/developer_belt"))
        if args.pack:
            command[1:1] = ["--main-pack", str(pack)]
        script_hash = hashlib.sha256((ROOT / "tests" / (name + ".gd")).read_bytes()).hexdigest()
        began = time.time()
        result = execute(command, destination, 600 if name == "terrain_tools_endurance" else 180, marker)
        row = {"test": name, "command": command, "cache": cache, "result": result,
               "script_sha256": script_hash}
        for source in [ROOT / "reports" / (name + ".json"), ROOT / "reports" / name / "result.json"]:
            if source.is_file() and source.stat().st_mtime >= began:
                shutil.copy2(source, destination / "measurements.json")
        if name in {"terrain_tools_endurance", "held_mining_flight"}:
            frames = ROOT / "reports/foundation_mining.frames.csv"
            if frames.is_file() and frames.stat().st_mtime >= began:
                shutil.copy2(frames, destination / "frames.csv")
        manifest["runs"].append(row)
        (folder / "suite.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(("PASS " if result["passed"] else "FAIL ") + name, flush=True)
    passed = all(row["result"]["passed"] for row in manifest["runs"])
    print(str(folder / "suite.json"), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

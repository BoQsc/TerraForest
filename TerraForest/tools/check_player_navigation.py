"""Check player map markers, compass and session/developer menus in isolated temporary worlds."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path

from play_checkpoint import revision_metadata
from prune_successful_test_caches import remove_owned_temporary_cache
from run import ROOT, parse_args
from run_godot_check import command_for, execute, verify_pack_native


CHECKS = {
    "map_marker_store": (30, "MAP_MARKER_STORE checks=", True),
    "player_navigation": (120, "PLAYER_NAVIGATION checks=", False),
    "vegetation_target_motion": (140, "VEGETATION_TARGET_MOTION checks=", False),
    "developer_vehicle_spawn": (110, "DEVELOPER_VEHICLE_SPAWN checks=", False),
    "developer_tools": (150, "DEVELOPER_TOOLS checks=", False),
    "session_player_page": (100, "SESSION_PLAYER_PAGE checks=", False),
    "world_map_teleport": (180, "WORLD_MAP_TELEPORT checks=", False),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--keep-cache", action="store_true")
    parser.add_argument("--checks", nargs="+", choices=CHECKS, default=list(CHECKS))
    options = parser.parse_args()
    settings, _ = parse_args([])
    native = verify_pack_native() if options.pack else {
        path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (ROOT / "addons").glob("*/bin/*.dll")
    }
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/checks" / (stamp + "_player_navigation" + ("_pack" if options.pack else ""))
    folder.mkdir(parents=True)
    results = []
    for name in options.checks:
        output = folder / name
        output.mkdir()
        timeout, marker, headless = CHECKS[name]
        extra = ["--gameplay-construction", "--world-generator=23", "--world-seed=1703", "--ground-cover",
                 "--navigation-evidence=" + str(output / "evidence"), "--vehicle-spawn-evidence=" + str(output / "evidence"),
                 "--player-page-evidence=" + str(output / "evidence"), "--map-travel-evidence=" + str(output / "evidence")]
        if name == "developer_vehicle_spawn":
            extra.append("--vehicle-fleet")
        command, cache = command_for(Path(settings.godot).resolve(), name, output, extra, headless)
        source = ROOT / "tests" / (name + ".gd")
        if options.pack:
            driver = output / (name + "_external.gd")
            driver.write_text(source.read_text().replace("res://reports", (output / "evidence").as_posix()), encoding="utf-8")
            command[command.index("--path") + 1] = str(ROOT / "dist")
            command[command.index("--script") + 1] = str(driver)
            command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        record = dict(test=name, command=command, cache=cache, utc=stamp, native_sha256=native,
                      test_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), **revision_metadata())
        if options.pack:
            record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
        manifest = output / "run.json"
        manifest.write_text(json.dumps(record, indent=2) + "\n")
        record["result"] = execute(command, output, timeout, marker)
        record["cache_retained"] = True
        if record["result"]["passed"] and not options.keep_cache:
            try:
                record["removed_owned_cache"] = remove_owned_temporary_cache(cache)
                record["cache_retained"] = False
            except (OSError, ValueError) as error:
                record["cache_cleanup_error"] = str(error)
        manifest.write_text(json.dumps(record, indent=2) + "\n")
        results.append(dict(test=name, **record["result"]))
        print(("PASS " if record["result"]["passed"] else "FAIL ") + str(output), flush=True)
    (folder / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())

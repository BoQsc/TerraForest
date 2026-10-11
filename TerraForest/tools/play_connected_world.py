# SPDX-License-Identifier: 0BSD
"""Open the verified local connected-settlement save without regenerating it."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
from run import ROOT, parse_args, launch_details
from play_checkpoint import record_and_run
from clone_world import clone_once


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--furnished", action="store_true", help="Open the separate furnished checkpoint")
    parser.add_argument("--generated-furnished", action="store_true", help="Open the editor-generated furnished checkpoint")
    parser.add_argument("--geology", action="store_true", help="Open the underground ore access checkpoint")
    parser.add_argument("--actors", action="store_true", help="Enable nearby actor simulation and free-editor controls")
    parser.add_argument("--vehicle-fleet", action="store_true", help="Enable bounded nearby vehicle activation")
    parser.add_argument("--gameplay-copy", action="store_true", help="Copy the furnished checkpoint once into a separate gameplay save")
    args = parser.parse_args()
    if args.gameplay_copy and not args.generated_furnished:
        parser.error("Gameplay copy requires --generated-furnished")
    if sum([args.furnished,args.generated_furnished,args.geology])>1:
        parser.error("Choose one checkpoint")
    relative = "docs/evidence/furnished_world/manifest.json" if args.furnished else "docs/evidence/connected_world/manifest.json"
    if args.generated_furnished:
        relative = "docs/evidence/generated_furnished/manifest.json"
    if args.geology:
        relative = "docs/evidence/geology_access/manifest.json"
    manifest = json.loads((ROOT / relative).read_text())
    slot = manifest["slot"]
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,47}", slot):
        parser.error("Checkpoint manifest has an invalid slot")
    save = Path(os.environ.get("APPDATA", "")) / "Godot/app_userdata/TerraForest/worlds" / (slot + ".trw")
    if not save.is_file() and not (args.gameplay_copy and (save.parent / "combined_gameplay.trw").is_file()):
        parser.error("This locally generated checkpoint save is missing. See docs/CONNECTED_WORLD_CHECKPOINT.md; the repository does not contain user saves.")
    source_slot = slot
    copy_info = None
    if args.gameplay_copy:
        slot = "combined_gameplay"
        copy_info = {"source_slot": source_slot, "slot": slot,
                     "created": False, "pending_first_launch": not (save.parent / (slot + ".trw")).exists()}
        if not args.dry_run:
            copy_info = clone_once(save.parent, source_slot, slot)
    launch_args = ["--slot", slot]
    if args.gameplay_copy:
        launch_args += ["--gameplay-construction"]
    if args.furnished or args.generated_furnished:
        launch_args += ["--ground-cover"]
    if args.geology:
        launch_args += ["--gameplay-construction", "--generator", str(manifest["generator"]), "--seed", str(manifest["seed"])]
    if args.godot:
        launch_args += ["--godot", args.godot]
    if args.actors:
        launch_args += ["--actors"]
    if args.vehicle_fleet:
        launch_args += ["--vehicle-fleet"]
    config, extra = parse_args(launch_args)
    details = launch_details(config, extra)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports' / 'playtests' / stamp
    details['command'][1:1] = ['--log-file', str(folder / 'engine.log')]
    details.update(label='Saved world checkpoint', utc=stamp, checkpoint_manifest=relative,
                   actors_enabled=args.actors, vehicle_fleet_enabled=args.vehicle_fleet, ground_cover_enabled=args.furnished or args.generated_furnished,
                   notes='Existing local save is edited in place. 60 FPS is a target, not qualification.')
    if args.gameplay_copy:
        details.update(label="Combined gameplay checkpoint", gameplay_copy=copy_info,
                       notes="Separate gameplay save; first run copies the furnished editor save, later runs retain gameplay progress.")
    if args.dry_run:
        print(json.dumps(details, indent=2))
        return 0
    return record_and_run(details, folder, details['label'])


if __name__ == "__main__":
    raise SystemExit(main())

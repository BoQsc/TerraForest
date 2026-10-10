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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--furnished", action="store_true", help="Open the separate furnished checkpoint")
    parser.add_argument("--generated-furnished", action="store_true", help="Open the editor-generated furnished checkpoint")
    parser.add_argument("--geology", action="store_true", help="Open the underground ore access checkpoint")
    parser.add_argument("--actors", action="store_true", help="Enable nearby actor simulation and free-editor controls")
    args = parser.parse_args()
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
    if not save.is_file():
        parser.error("This locally generated checkpoint save is missing. See docs/CONNECTED_WORLD_CHECKPOINT.md; the repository does not contain user saves.")
    launch_args = ["--slot", slot]
    if args.furnished or args.generated_furnished:
        launch_args += ["--ground-cover"]
    if args.geology:
        launch_args += ["--gameplay-construction", "--generator", str(manifest["generator"]), "--seed", str(manifest["seed"])]
    if args.godot:
        launch_args += ["--godot", args.godot]
    if args.actors:
        launch_args += ["--actors"]
    config, extra = parse_args(launch_args)
    details = launch_details(config, extra)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = ROOT / 'reports' / 'playtests' / stamp
    details['command'][1:1] = ['--log-file', str(folder / 'engine.log')]
    details.update(label='Saved world checkpoint', utc=stamp, checkpoint_manifest=relative,
                   actors_enabled=args.actors, ground_cover_enabled=args.furnished or args.generated_furnished,
                   notes='Existing local save is edited in place. 60 FPS is a target, not qualification.')
    if args.dry_run:
        print(json.dumps(details, indent=2))
        return 0
    return record_and_run(details, folder, 'Saved world checkpoint')


if __name__ == "__main__":
    raise SystemExit(main())

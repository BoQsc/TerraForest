# SPDX-License-Identifier: 0BSD
"""Open the verified local connected-settlement save without regenerating it."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from run import ROOT, parse_args, launch_details


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
    if args.dry_run:
        print(json.dumps(details, indent=2))
        return 0
    return subprocess.call(details["command"])


if __name__ == "__main__":
    raise SystemExit(main())

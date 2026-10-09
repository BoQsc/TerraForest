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
    args = parser.parse_args()
    manifest = json.loads((ROOT / "docs/evidence/connected_world/manifest.json").read_text())
    slot = manifest["slot"]
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,47}", slot):
        parser.error("Checkpoint manifest has an invalid slot")
    save = Path(os.environ.get("APPDATA", "")) / "Godot/app_userdata/TerraForest/worlds" / (slot + ".trw")
    if not save.is_file():
        parser.error("This locally generated checkpoint save is missing. See docs/CONNECTED_WORLD_CHECKPOINT.md; the repository does not contain user saves.")
    launch_args = ["--slot", slot]
    if args.godot:
        launch_args += ["--godot", args.godot]
    config, extra = parse_args(launch_args)
    details = launch_details(config, extra)
    if args.dry_run:
        print(json.dumps(details, indent=2))
        return 0
    return subprocess.call(details["command"])


if __name__ == "__main__":
    raise SystemExit(main())

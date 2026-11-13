# SPDX-License-Identifier: 0BSD
"""Headless normal UI creation/continuation, with two receipt-owned fixtures."""
import argparse
import hashlib
import json
import os
from pathlib import Path
from development_storage import admit, ROOT
from run_godot_check import execute


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["create", "reopen", "continue"])
    args = parser.parse_args()
    slot = "LauncherUI_1703_Final"
    world = Path(os.environ["APPDATA"]) / "Godot/app_userdata/TerraForest/worlds" / (slot + ".trw")
    if args.phase == "create" and world.exists():
        raise SystemExit("Owned fixture already exists; use reopen or continue. Never overwrite it to rerun creation.")
    folder = ROOT / "reports/launcher_generation" / args.phase
    admission = admit(report_bytes=16*2**20, world_bytes=128*2**20 if args.phase == "create" else 0)
    folder.mkdir(parents=True, exist_ok=True)
    command = [str(ROOT / "TerraForest.exe"), "--headless", "--path", str(ROOT),
               "--script", "res://tests/launcher_world_flow.gd", "--", "--launcher-slot="+slot]
    if args.phase == "create":command.append("--launcher-create")
    if args.phase == "continue":command.append("--continue-last")
    receipt = {"slot": slot, "command": command, "admission": admission,
               "driver_sha256": hashlib.sha256((ROOT / "tests/launcher_world_flow.gd").read_bytes()).hexdigest(),
               "lifecycle": "Retain at most Fixed and Final launcher regression worlds; receipt-owned, no player saves retired."}
    (folder / "ownership.json").write_text(json.dumps(receipt, indent=2))
    registry = ROOT / "reports/artifact_retention/owned_worlds.json"
    owned = json.loads(registry.read_text()) if registry.exists() else {}
    owned[slot] = {"last_report": str(folder.relative_to(ROOT)), "ownership_receipt": str((folder / "ownership.json").relative_to(ROOT))}
    registry.write_text(json.dumps(owned, indent=2))
    diagnostic = world.with_suffix(".diagnostic.json")
    marker = diagnostic.read_bytes() if diagnostic.exists() else None
    try:
        if marker is not None:diagnostic.unlink()
        result = execute(command, folder, 360 if args.phase == "create" else 150, "LAUNCHER_WORLD_FLOW ready=true")
    finally:
        if marker is not None:diagnostic.write_bytes(marker)
        elif world.exists():
            diagnostic.write_text(json.dumps({"purpose": "Owned launcher regression", "ownership_receipt": str(folder / "ownership.json")}))
    (folder / "run.json").write_text(json.dumps({**receipt, "result": result}, indent=2))
    print(("PASS " if result["passed"] else "FAIL ") + str(folder))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

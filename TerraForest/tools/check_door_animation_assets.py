# SPDX-License-Identifier: 0BSD
"""Reject stale authored door motion before exporting the game."""
import json

from prepare_bg5_runtime import ROOT, sha, verify


def check():
    verify()
    record = json.loads((ROOT / "addons/structures/door_animation/provenance.json").read_text())
    checks = {
        "authoring/bg5/BG5.Door.Parts.glb": record["source_sha256"],
        "tools/bake_door_animation.gd": record["tool_sha256"],
        "tools/bake_bg5_runtime.gd": record["base_tool_sha256"],
        "mods/bg5_runtime/bake.json": record["base_receipt_sha256"],
        "addons/structures/door_animation/bg5_motion.scn": record["output_sha256"],
    }
    for path, expected in checks.items():
        if sha(ROOT / path) != expected:
            raise ValueError("Stale authored door animation: " + path)
    for name in ("Open", "Close"):
        clip = record["clips"][name]
        if not 1.14 < clip["seconds"] < 1.16 or {
            channel["node"]: channel["keys"] for channel in clip["channels"]
        } != dict.fromkeys(("DoorPivot", "HandleFrontPivot", "HandleBackPivot", "LatchPivot"), 70):
            raise ValueError("Authored door clip channels changed: " + name)
    print("PASS authored door source, bake tools, fitted mesh receipt and runtime rig match")


if __name__ == "__main__":
    check()

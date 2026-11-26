# SPDX-License-Identifier: 0BSD
"""Record or verify exact original Homestead authoring and asset identities."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def record(number):
    name = f"homestead_{number:02}"
    folder = ROOT / "addons/structures/packs" / name
    manifest = json.loads((folder / "pack.json").read_text(encoding="utf-8-sig"))
    assets = [folder / "pack.json", folder / "icons.trtex"]
    assets += [folder / "models" / (row["id"] + ".tres") for row in manifest["objects"]]
    driver = "homestead_pack" if number == 1 else f"homestead_{number:02}_pack"
    source = [folder / "author.gd", folder / "catalog.gd", ROOT / "tests" / (driver + ".gd")]
    if number >= 3:
        source.append(ROOT / "addons/structures/packs/homestead_02/author.gd")
    if number >= 5:
        source.append(ROOT / "addons/structures/packs/homestead_04/author.gd")

    if number == 9:
        source.append(ROOT / "addons/structures/packs/homestead_07/author.gd")

    def hashes(paths):
        return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(paths)}

    return {
        "schema": 1, "pack": manifest["id"], "version": manifest["version"],
        "creator": "TerraForest contributors, authored with Codex", "date": "2026-11-26",
        "origin": "Original parametric geometry and procedural materials; no external asset inputs",
        "asset_license": "CC0-1.0", "code_license": "0BSD",
        "terms_evidence": "CONTRIBUTING.md and adjacent ASSET_LICENSE.md",
        "authoring_tool": "Existing Godot 4.7.2 Steam; external engine, not vendored by this pack",
        "brief": "A separate recognizable household pack with the user-approved roster and a rendered preview of its actual meshes",
        "author_command": f'python tools/run_godot_check.py {driver} --require "failures=0" -- --author-pack',
        "icon_command": f'python tools/run_godot_check.py {driver} --isolated-render --require "failures=0" -- --preview-only',
        "source_sha256": hashes(source), "asset_sha256": hashes(assets),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for number in (1, 2, 3, 4, 5, 6, 7, 8, 9):
        value = record(number)
        output = ROOT / "addons/structures/packs" / f"homestead_{number:02}" / "provenance.json"
        content = json.dumps(value, indent=2) + "\n"
        if args.check:
            if not output.is_file() or output.read_text(encoding="utf-8") != content:
                parser.exit(1, f"Stale Homestead {number:02} provenance; run tools/homestead_provenance.py\n")
        else:
            output.write_text(content, encoding="utf-8")
    print("PASS Homestead 01/02/03/04/05/06/07/08/09 provenance " + ("verified" if args.check else "recorded"))


if __name__ == "__main__":
    main()

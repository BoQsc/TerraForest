# SPDX-License-Identifier: 0BSD
"""Record exact original building recipes, baked data and inherited material inputs."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "addons/structures/grand_buildings"


def hashes(paths):
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths)}


def record():
    inputs = [ROOT / p for p in (
        "addons/structures/mansion/author.gd", "addons/structures/mansion/provenance.json",
        "reviews/city_buildings/recipes.gd", "reviews/building_expansion/recipes.gd",
        "addons/structures/textures/expansion_v2/provenance.json",
        "addons/structures/objects/wooden_door.object.json",
        "addons/structures/prefabs/window_model.tres")]
    inputs += list((ROOT / "addons/structures/packs").glob("homestead_*/provenance.json"))
    return dict(schema=1, id="terraforest.grand_buildings_r1", date="2026-11-27",
                creator="TerraForest contributors, authored with Codex",
                origin="Original floor plans and cell/furnishing arrangements; no external reference assets",
                brief="Three buildings larger than Homestead Manor: many flats, a cathedral twice every envelope axis with deep basements, and a crowded-street residential tower",
                asset_license="CC0-1.0", code_license="0BSD",
                terms_evidence="CONTRIBUTING.md and adjacent ASSET_LICENSE.md",
                authoring_tool="Existing external Godot 4.7.2 Steam; inherited model/material terms are unchanged",
                source_sha256=hashes([FOLDER / "author.gd", FOLDER / "catalog.gd",
                                     ROOT / "tests/grand_buildings.gd", ROOT / "tests/grand_buildings_world.gd"]),
                input_sha256=hashes(inputs),
                asset_sha256=hashes([FOLDER / (name + ".tres") for name in
                                     ("courtyard_flats", "grand_cathedral", "street_tower")]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    contents = json.dumps(record(), indent=2) + "\n"
    target = FOLDER / "provenance.json"
    if args.check:
        if not target.is_file() or target.read_text(encoding="utf-8") != contents:
            parser.exit(1, "Stale grand building provenance; run tools/grand_building_provenance.py\n")
    else:
        target.write_text(contents, encoding="utf-8")
    print("PASS grand building provenance " + ("verified" if args.check else "recorded"))

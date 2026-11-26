# SPDX-License-Identifier: 0BSD
"""Record/check original Outdoor 01 and Homestead Manor authoring inputs and bakes."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def hashes(paths):
    return {str(path): hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in sorted(set(paths))}


def records():
    pack = "addons/structures/packs/outdoor_01"
    manifest = json.loads((ROOT / pack / "pack.json").read_text(encoding="utf-8"))
    common = dict(schema=1, creator="TerraForest contributors, authored with Codex", date="2026-11-26",
                  asset_license="CC0-1.0", code_license="0BSD", authoring_tool="Existing external Godot 4.7.2 Steam",
                  terms_evidence="CONTRIBUTING.md and adjacent ASSET_LICENSE.md")
    source = [f"{pack}/author.gd", f"{pack}/catalog.gd", "tests/outdoor_01_pack.gd"]
    source += [f"addons/structures/packs/homestead_{number:02}/author.gd" for number in (2, 4, 7, 10)]
    assets = [f"{pack}/pack.json", f"{pack}/icons.trtex"]
    assets += [f"{pack}/models/{row['id']}.tres" for row in manifest["objects"]]
    yield f"{pack}/provenance.json", dict(common, pack=manifest["id"], version=manifest["version"],
          origin="Original parametric outdoor models and procedural materials; no external assets",
          brief="Separate outdoor container/prop pack: nest, duffel, boxes, tires, litter, refuse bag, can and dumpster",
          source_sha256=hashes(source), asset_sha256=hashes(assets))
    mansion = "addons/structures/mansion"
    source = [f"{mansion}/author.gd", f"{mansion}/catalog.gd", "tests/homestead_mansion.gd",
              "addons/structures/outdoor_scatter.gd", "reviews/city_buildings/recipes.gd",
              "reviews/building_expansion/recipes.gd"]
    inputs = ["addons/structures/prefabs/window_model.tres", "addons/structures/objects/wooden_door.object.json",
              "addons/structures/textures/expansion_v2/provenance.json"]
    inputs += [p.relative_to(ROOT).as_posix() for p in (ROOT / "addons/structures/packs").glob("*/provenance.json")]
    yield f"{mansion}/provenance.json", dict(common, id="terraforest.homestead_manor_r2",
          origin="Original courtyard building arrangement; inherited models/materials retain separate notices",
          brief="Large two-storey courtyard mansion with rooms for all 100 Homestead objects and an outdoor service yard",
          source_sha256=hashes(source), input_sha256=hashes(inputs),
          asset_sha256=hashes([f"{mansion}/homestead_manor.tres"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for name, record in records():
        target = ROOT / name
        content = json.dumps(record, indent=2) + "\n"
        if args.check:
            if not target.is_file() or target.read_text(encoding="utf-8") != content:
                parser.exit(1, f"Stale {name}; run tools/object_content_provenance.py\n")
        else:
            target.write_text(content, encoding="utf-8")
    print("PASS Outdoor 01 / Homestead Manor provenance " + ("verified" if args.check else "recorded"))


if __name__ == "__main__":
    main()

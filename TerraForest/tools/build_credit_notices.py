# SPDX-License-Identifier: 0BSD
"""Bundle the retained source notices for the offline in-game license viewer."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/credits/notices.json"
NOTICES = [
    ("project", "TerraForest project code", "0BSD", "LICENSE.txt",
     "Use, copy, modify and distribute the project code, including commercially, under Zero-Clause BSD. Separately identified components retain their own terms."),
    ("spruce", "Spruce tree assets", "CC0 1.0", "addons/vegetation/ASSET_LICENSE.md",
     "The supplied spruce model, extracted images and derived bakes retain the source's stated CC0 dedication."),
    ("characters", "Character assets", "CC0 1.0 / inherited provenance", "addons/characters/LICENSE.txt",
     "Original character work is dedicated under CC0. The retained notice explains the inherited character source and the scope of that dedication."),
    ("woodland", "Original woodland sample", "0BSD", "LICENSE.txt",
     "Original woodland stones, plants, grass and procedural textures are identified as 0BSD in the woodland sample's authoring notes."),
    ("vehicle", "Vehicle model and demo", "0BSD", "vehicle_demo/LICENSE.txt",
     "The supplied vehicle model and demo code were declared the author's own 0BSD work. Native bindings retain their separate MIT notice."),
    ("bg5", "BG5 door and furniture assets", "CC0 1.0", "addons/structures/prefabs/BG5_LICENSE.md",
     "User-supplied door, chest, chair, table and bookshelf masters and runtime derivatives, with explicit contributor CC0 authorization and retained source provenance."),
    ("terrain_textures", "Inherited terrain textures", "Retained source provenance", "addons/volumetric_terrain/terrain_textures/THIRD_PARTY_TEXTURES.md",
     "These inherited textures retain their source terms. The supplied note does not establish a new 0BSD or CC0 grant; consult the original asset metadata before reusing them separately."),
    ("godot_logo", "Godot logo and boot artwork", "CC BY 4.0", "assets/branding/GODOT_LOGO_LICENSE.txt",
     "Godot logo by Andrea Calabró. The original artwork is centered at native size; TerraForest adds its own footer. Attribution and the license link follow."),
    ("godot_cpp", "godot-cpp native bindings", "MIT", "addons/world_runtime/GODOT_CPP_LICENSE.md",
     "The Godot C++ bindings used by the native addons retain this MIT notice."),
    ("godot_abi", "Godot GDExtension interface", "MIT", "addons/volumetric_terrain/native/GODOT_INTERFACE_LICENSE.txt",
     "The Godot GDExtension C ABI declarations retain the engine contributors' MIT notice."),
    ("meshoptimizer", "meshoptimizer", "MIT", "addons/structures/MESHOPTIMIZER_LICENSE.txt",
     "Mesh optimization by Arseny Kapoulkine. The structures addon retains the following MIT notice."),
]


def bundle():
    return {"schema": 1, "notices": [
        dict(id=key, title=title, license=license_name, source=source,
             summary=summary, text=(ROOT / source).read_text(encoding="utf-8").strip())
        for key, title, license_name, source, summary in NOTICES
    ]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the offline bundle is stale")
    args = parser.parse_args()
    content = json.dumps(bundle(), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text(encoding="utf-8") != content:
            parser.exit(1, "Credit notices are stale; run tools/build_credit_notices.py\n")
        print(f"PASS: all {len(NOTICES)} offline notices match their retained source files")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(content, encoding="utf-8")
        print(f"Created {OUTPUT}")


if __name__ == "__main__":
    main()

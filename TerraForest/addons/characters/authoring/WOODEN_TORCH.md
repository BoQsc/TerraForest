# Wooden torch — first draft, 2026-10-26

Editable source: `Human.torch.blend`. The preserved Human R11 delivery is unchanged.
The mesh, procedural PBR images and animation are authored locally by
`tools/author_wooden_torch.py`; no downloaded models or textures were used.
Geometry and scripts follow the repository's 0BSD license.

The 60.5 cm torch has 20,230 vertices / 40,032 triangles, an irregular wooden
shaft, overlapping linen winding with real thickness, and a split charred crown.
Three materials each have packed 1024px base-color, roughness and normal maps.
Godot imports the GLB with automatic LODs. Extracted `Torch_Torch*.png` files are
the importer's copies of those packed images and are required runtime resources.

The original 59-bone rig receives new 60 Hz idle, walk, run and jump actions.
The right hand and finger wrap stay fixed relative to Weapon_Axe; the left hand
rests low. Corrected hand weights reuse the existing unarmed body. Crouch derives
from the existing grounded crouch, with the torch's complete upper-body pose
translated by the hip displacement. Native player movement remains the sole owner.

Regenerate from the repository root with Blender background mode, opening
`addons/characters/Human_R11_Complete_Repost/Human.r11.blend` and running
`tools/author_wooden_torch.py`. Then run Godot's
`tools/import_wooden_torch.gd`, editor import, and `tests/bake_item_icons.gd`
with `--icons-only --icon-items=1,2,3,5,6,501`.

Runtime fire uses a camera-facing turbulent flame, 16 shader-animated embers,
eight faint smoke wisps and one gently varying shadowed OmniLight3D. No
per-ember physics or unbounded spawning. Switching slots/placement hides the
effect and removes light energy; hidden player presentation also emits no light.

Item 6 is craftable for one Wood (102) and two Plant (204), or available from the
existing Dev Bag. It lights automatically while held and supports native
inventory, container and pickup persistence. Old inventories are not topped up.
This pass does not implement fuel depletion, ignition controls, underwater
extinguishing, fire damage/spread, torch melee or sound. Dropped torches are static
unlit collectibles. Those systems need separate gameplay decisions if requested.

Appearance, flame style and hand placement await player review. Engineering
checks do not imply visual acceptance. Preview and evidence:
`docs/evidence/wooden_torch/README.md`.

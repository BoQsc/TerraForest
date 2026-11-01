# Trail clothing pack, revision 1

SPDX-License-Identifier: CC0-1.0

To the extent possible under law, TerraForest contributors dedicate the original
trail garment geometry, materials, fabric pattern, weights and non-code authoring
data in this delivery to the public domain under CC0 1.0 Universal, including its
fallback license and warranty disclaimer. Authored with OpenAI Codex on 2026-11-01
at the maintainer's request to apply the woven outfit to the trader and try further
3D clothing packs, under the repository's contribution terms.

Full legal text: https://creativecommons.org/publicdomain/zero/1.0/legalcode

## Exact scope and provenance

- `304.res`, `305.res`, `306.res`: original broad-brimmed hat, belted jerkin and
  tall boots; embedded materials and ten named skin influences.
- `304.glb`, `305.glb`, `306.glb`: unrigged portable garment-only exports. No
  inherited character body, skeleton or animation is included.
- `304__albedo.png`, `305__albedo.png`: Godot-extracted copies of the embedded
  original periodic weave pattern. `.import` sidecars are generated import metadata.
- `manifest.json` and `derivatives.json`: original provenance and output receipts.
- `../../../player_runtime/art/drops/304.res`, `305.res`, `306.res`: normalized
  garment derivatives, baked with the original project's item-bake tool.
- Only tiles 304–306 of `../../../player_runtime/art/item_icons.trtex`: rendered
  garment derivatives. Other tiles retain their existing terms and provenance.

`tools/author_trail_clothes.gd` independently authors the new hat crown/brim/band,
jerkin panels/fastenings/belt/pouch and boot shafts/laces/cuffs. It reuses original
0BSD primitive/weight/material helpers from `tools/author_woven_clothes.gd`.
Both scripts remain 0BSD. No external model, texture pack, reference image or
third-party code was imported. The exact recipes, hashes, user intent and external
Godot version are recorded in the manifest; Godot and Codex are authoring tools,
not components distributed with this pack.

The retained R11 body was inspected for fit within its existing runtime scope.
No R11 mesh, rig or texture is copied into these portable exports. Screenshots
showing that body and the runtime character retain `addons/characters/LICENSE.txt`
and GAP-002 in the license inventory. This asset dedication does not resolve or
widen that inherited provenance claim.

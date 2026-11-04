# Current pickaxe and hatchet drop meshes

`1.res` and `2.res` are refreshed versions of the existing pickaxe/hatchet pickup
assets, extracted from the same Human R11 equipment currently used by held tools
and inventory icons. This is maintenance of those existing representations, not
intake of a new model pack or an independent license grant.

Source: `addons/characters/runtime/assets/Human.r11.glb`, SHA-256
`0dc8fdbcfac451f61b6eee5c914b1e79f5ec450f5e98e4c896e8b46370bf35c8`.
It is the user-supplied R11 repost recorded in
`addons/characters/Human_R11_Complete_Repost/README.txt`. The equipment materials
declare CC0-1.0 in their embedded glTF metadata. Retain the inherited character
notices and qualifications in `addons/characters/LICENSE.txt`,
`addons/characters/README.md` and inventory record GAP-002; this conversion does
not resolve the inherited provenance review or relicense third-party rights.

Original AI-assisted bake code: `tools/tool_drop_bake.gd` and
`tools/bake_tool_drops.gd`, under 0BSD. `current_tool.gdshader` is original 0BSD
rendering code. Existing Godot is used as an external build tool. No external
model, texture, code snippet or image was imported for this correction.

Each asset preserves the current model's complete tool geometry, wood texture
and normal detail, with per-vertex base color, roughness and metallic properties
merged into one batchable surface. Player geometry, skinning and animation are
excluded. The existing 35 cm normalization and item/save identities are retained.
Exact input/output hashes and source triangle counts are recorded in
`current_tools.bake.json`. Launch/export preflight checks and rebuilds these
assets even when icon textures are already current.

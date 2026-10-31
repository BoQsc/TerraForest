# BG5 runtime exports

CC0-1.0 derivatives of the unchanged user-supplied masters in `authoring/bg5/`.
See `addons/structures/prefabs/BG5_LICENSE.md` and the generation receipt
`bake.json`. Geometry is consolidated by material, textures are bounded to 1024
pixels on their long edge, and authoring animation clips are omitted.

The game uses the baked shared meshes at the existing prefab paths. These GLBs
are portable equivalents for modding. To exercise the door as a loose visual
replacement, copy this directory into `user://mods/bg5_runtime/` and add
`user://mods/bg5_runtime/door.objects.json` to `[objects] manifests` in
`user://mods/enabled.cfg`. The original model ID, hinge and collision remain.

`door_leaf.glb` is the moving part; `door_frame.glb` is a stationary companion
in the same coordinate system. The frame is prepared but is not automatically
placed or rotated with existing doors. Furniture/chest GLBs are static closed
meshes; their original parts and animations remain in the editable masters.
Furniture visual overrides through `[objects]` are not implemented by this pack.

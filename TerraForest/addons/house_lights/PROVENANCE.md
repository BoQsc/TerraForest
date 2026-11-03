# House-light props

- New original source code: 0BSD, AI-assisted TerraForest work, 2026-11-03.
- New original GLB meshes and their JSON authoring definitions: CC0-1.0.
- Original authoring source: `tools/author_house_lights.gd`; independently assembled
  primitive geometry and original material parameters, no external art or references.
- Authoring brief: breakable GLB lamps, standing torches and freestanding fireplaces
  for house rooms, with ordinary resource salvage and efficient pooled illumination.
- Original `flame.gdshader` is procedural code, licensed 0BSD; no image textures,
  sampled fire footage, externally supplied meshes or new third-party tools are used.
- Exact original assets: `assets/room_lamp.glb`, `assets/standing_torch.glb`,
  `assets/iron_fireplace.glb`, `room_lamp.json`, `standing_torch.json`,
  `iron_fireplace.json` and `house_lights.module.json`.
- Matching original baked derivatives: `assets/room_lamp_model.res`,
  `assets/standing_torch_model.res` and `assets/iron_fireplace_model.res`.
  These retain the GLB geometry/materials and offline-derived LODs. Each stores
  its source GLB SHA-256; source changes require an explicit authoring rebake.
- GLBs are editable source assets; native batched runtime presentation uses their
  admitted shared meshes. Existing engine/addon dependencies retain their notices.
- No building grid, house prefab or saved player construction is redefined.

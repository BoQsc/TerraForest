# Gameplay items, hands and direct gathering

Verified 2026-10-11. Original project assets/code remain 0BSD.

- Gameplay: 18 checks: all 22 native batched drop meshes have one surface, topsoil versus deeper stone native accounting, exact direct inventory rewards, duplicate receipts, bounded overflow/recovery after restore, unarmed shared damage without wear, real RMB paid wood placement, Space with/after Alt, G and repeated adjacent drops.
- Shared attacks: 53 checks across terrain, blocks, trees, ground cover, furniture, actors and vehicles, including wear and protected contents.
- Movement/terrain surface: 27 checks; fullscreen 1920x1080.
- Automatic rewards UI: 6 checks for direct stone/ore/topsoil delivery, dirty notification, duplication prevention, crafting and inventory restore.
- Mining persistence: 25 checks across actual terrain worker publication, repeated empty excavation, crafting/building, explicit save, fresh-worker restore, graceful shutdown and interrupted edit protection.
- Drop transactions: 16 checks; native atomicity, capacity/stale/reentrant rejection.
- Visual: actual native MultiMesh drop catalog and first-person hands screenshots inspected.

No sustained frame-time or old-laptop performance claim is made. Drop rendering retains the existing per-type 256 visible instance cap and bounded spatial refresh. Every item uses one baked mesh surface; tools/clothing merge authoring parts into vertex-colored geometry. No per-drop nodes, active rigid bodies or mesh generation. Baked meshes occupy about 1.35 MB on disk; the shared icon atlas remains 2 MiB RGBA. Reproduce assets with `python tools/run_godot_check.py bake_item_icons --timeout 35 --require 'failures=0'` while the game is closed. Both terrain extension variants rebuilt against the pinned prebuilt SDK; godot-cpp itself was not rebuilt.

Topsoil is item 211, receipt category 10, using a two-metre natural surface-depth rule. Terrain persistence/shader material IDs are unchanged. Yield remains one item per newly excavated lattice sample, not physical volume. Ores/clothing and hands use the current simple art; they are not final realistic assets. G drops one unit; mouse drag still drops whole/half stacks. Full inventory overflow is retained internally and delivered automatically as space opens, with further mining paused. Saved old `pending_rewards` sections remain compatible. Missing Topsoil pickup sections restore empty through the existing component defaults.

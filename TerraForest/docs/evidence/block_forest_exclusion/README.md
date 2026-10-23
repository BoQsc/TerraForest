# Brick placement preserves surrounding trees

2026-10-23. Reproduced from the Character Preview launch configuration:
temporary generator 1 / seed 1703, gameplay construction, zombies, slot 5 brick,
and the actual right-click input path. This launcher uses the main world scene.

The construction exclusion query incorrectly used the entire source tree AABB
grown by two metres for wind. A brick at (807, 49, 1305), clear of every solid
trunk, intersected three overlapping canopy boxes. The old code removed trees
23482, 23483 and 23488 and their shadow casters. Tree count fell from 2,724 to
2,721. This was a logical exclusion error; the trees were removed, not briefly
hidden by shadow-map refresh. The old test expectation also permitted canopy
removal, so it failed to protect this ordinary gameplay case.

`VegetationWorld.placement_bounds()` now uses the same 0.7 × 8 × 0.7 m local solid
trunk bounds as the native collision proxy. Instance scaling and rotation still
apply through the existing native overlap query. Rendering retains independent
wind-safe bounds. Buildings can still exclude genuinely obstructed trunks;
overhanging crowns alone do not clear surrounding trees. This does not add a new
mesher, query pass, renderer or per-frame task.

The full-world regression now retains all 2,724 trees and 3,179 visible tree/shadow
MultiMesh records. Four checked rendered frames preserve transforms and fade
packets exactly. Canopy revision and forest rebuild count remain unchanged, so
the otherwise unnecessary shadow-mask/forest rebuild is avoided. The inventory
brick count decreases from 64 to 63. Inspected `before.png` and `after.png` show
the retained surrounding trees and shadows at 1920 × 1080. These are functional
and rendering-continuity checks, not sustained performance or thermal proof.

Checks:

- `baseline_failure.log` / `baseline_failure.run.json`: retained failing native
  gameplay reproduction before the correction.
- `world.log` / `world.run.json` / `result.json`: corrected Character Preview
  route, zero failures.
- `trunk_continuity.log` / `trunk_continuity.run.json`: a block through one trunk
  removes that tree while preserving the other 15 trees and their rendered
  shadow/visual records across four checked frames.
- `frontage.log` / `frontage.run.json`: native frontage exclusion, unaffected
  roots, trunk proxies, undo/redo and snapshot restoration remain correct.
- `initial_timeout.log` / `initial_timeout.run.json`: the first isolated rendered
  check exceeded its 25-second process deadline. It was not accepted as a pass;
  the subsequent completed checks are recorded separately.

Commands:

```text
python tools/run_godot_check.py block_forest_world --timeout 60 --require BLOCK_FOREST_WORLD -- --world-generator=1 --gameplay-construction --zombies
python tools/run_godot_check.py block_forest_continuity --timeout 30 --require BLOCK_FOREST_CONTINUITY
python tools/run_godot_check.py frontage_vegetation --headless --timeout 25 --require FRONTAGE_VEGETATION
```

User saves are not edited. Exclusion is procedural, so reopening an affected
world recomputes eligibility with the corrected bounds. This change does not
close the separately tracked terrain-edit latency, selective storage residency,
whole-world generation/visual coverage or populated-runtime requirements.

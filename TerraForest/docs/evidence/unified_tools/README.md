# Unified actions and gameplay tools — 2026-10-11

This replaces inventory mode selectors with functional local gameplay tools
and docks detailed editor palettes into one Actions window. Existing item IDs,
native inventory/storage formats and native accounting are retained. There is
no native binary or dependency change in this delivery.

`unified_tools.log` passes 44 checks and covers real mouse drags, Shift splitting, keyboard and mouse
selection of empty hands, material selection without editing, removal of an
equipped tool, and mouse navigation through Equipment, Building and Objects.
It checks development-only controls, preservation of settlement/prefab/road
details, `~+F` flight without a headlamp change or double toggle, restoration
of gameplay, and E opening a chest while holding an assembly tool. It also
uses actual held mouse input to publish a native pickaxe excavation, validates
its fixed reach/radius/no-fill policy and verifies empty hands cannot keep mining.

`hatchet.log` checks occlusion, reach, mouse-triggered harvesting, stable tree
identity, four-wood accounting and repeat-harvest rejection. `furniture.log`
checks paid object placement, collision, selection, dismantling, native removal
and 3/1/4-wood salvage. `storage_build.log` and `storage_reopen.log` each pass
20 checks, covering compound saves, separate-process reopen, same-process reload,
native contents protection and deletion after emptying. `player_hud_smoke.log`
retains flight/motion, palette constraints, native loadout capture/restore and
pose readiness coverage under the new input contract. It also checks that
clicking inventory slots only selects and cannot move items. Test saves are isolated.

Screenshots were reviewed at fullscreen 1920x1080 with the configured 60 FPS cap.
These brief functional fixtures are not a sustained frame-time or thermal
qualification: low instantaneous FPS during startup/fixture work is visible.
Held tool meshes are simple original geometry; durability, crafting/repair,
polished hands/animation, balancing and human usability acceptance remain open.

The retained initial aim fixture fails one chest check because it reused a
camera aim after multiple synthetic cursor/capture transitions. Re-aiming at
the known chest before pressing E fixes the fixture; the final run passes.
An earlier parse failure from mixed indentation in newly inserted script code
was corrected before these functional runs. The retained `initial_click_fixture` also catches missed synthetic UI clicks.
The helper now waits for layout/warp delivery, sets the pressed mouse mask and
flushes injected input; final logs record both down and up reaching each button.
No functional assertion was removed to obtain the passing results.

Reproduce from the repository root:

```powershell
python TerraForest/tools/run_godot_check.py unified_tools --timeout 65 --require 'UNIFIED_TOOLS failures=0' -- --gameplay-construction
python TerraForest/tools/run_godot_check.py harvesting_scene --timeout 60 --require HARVESTING_SCENE -- --gameplay-construction
python TerraForest/tools/run_godot_check.py furniture_world --timeout 60 --require FURNITURE_WORLD -- --gameplay-construction
python TerraForest/tools/check_storage_world.py
```

Run manifests retain commands, engine/native fingerprints and working revision
provenance. `source_hashes.json` records the final scripts.

# Session menu and tool-owned controls

2026-10-24. Escape now consistently opens Session and Destinations. The duplicate
belt selector and Building, Objects, Vegetation, Development, Roads and Water
navigation have been removed from this menu. Save/load, headlamp, development
mode, browser and quit remain session actions. Tab and M retain inventory/map.

The existing quick HUD belongs to the selected tool. Hold Alt to interact with
it or click the actual belt. Building, Objects and Roads open their detailed
controls in an independent scrollable workspace. World tools owns diagnostics,
vehicle and water authoring; Actors owns its placement/orders/resident actions.
Terrain retains both grid-box and sculpt-box variants. Tool selection stays
nonmodal, including wheel traversal. Escape closes an open workspace to aiming;
the next Escape opens Session. Alt release preserves cursor ownership while a
workspace, inventory or session window is open. F1 controls quick-panel visibility.

Gameplay construction, objects and vegetation also expose contextual controls.
Recipe costs, owned-stack checks and development-only restrictions still apply.
No native stores, save formats, physics, generation or simulation were rewritten.
UI refreshes on existing equipment/menu events, without new world polling.

## Verification

- `developer_belt`: 34 checks, including all original belt mappings, box variant,
  unchanged carried inventory, nonmodal wheel selection, separate road/water/world
  windows, Escape during Alt interaction, inventory cursor handoff, gameplay
  construction and rejection of development water tools in gameplay.
- `player_hud_smoke`: 34 checks, including palette choices, inventory movement,
  saved loadout/pose restoration, input blocking and first-owned-tool admission.
- `unified_tools`: 51 checks, including actual mouse clicks from the Alt HUD into
  building settings, empty-slot selection on the actual belt, chest/inventory
  drags, paid construction restrictions, flight chords and real terrain editing.
- `building_object_menu`: 6 checks. Every production object choice scrolls into
  view and retains selection on closing; the workspace fits fullscreen 1080p.
- `water_editor_actions`: 17 checks. Actual moved water controls retain unit
  placement/removal, no-hit notices and rejection while terrain edits are busy.

Run manifests, logs, counts and inspected 1920x1080 screenshots are retained here.
These are finite functional checks, not a sustained frame-time qualification or
human acceptance of the complete UI/world. The package startup log is also
retained. An external assertion script also runs all 34 belt/focus checks against
the packed game resources and libraries, without a source-project resource root.
These checks do not establish clean-machine installation.

```powershell
python tools/run_godot_check.py developer_belt --timeout 70 --require 'failures=0' -- --gameplay-construction --ground-cover
python tools/run_godot_check.py player_hud_smoke --timeout 90 --require 'failures=0'
python tools/run_godot_check.py unified_tools --timeout 100 --require 'failures=0' -- --gameplay-construction
python tools/run_godot_check.py building_object_menu --timeout 65 --require 'failures=0' -- --gameplay-construction
python tools/run_godot_check.py water_editor_actions --timeout 85 --require 'failures=0' -- --gameplay-construction --water-gameplay --water-bucket-review
```

## Retained failed checks

The first belt check exposed a missing gameplay quick-panel refresh; equipment
changes now refresh it through the existing equip event. The first visual review
also exposed a tool-window minimum-height overflow; the bounded scroll layout
and regression assertion correct it. The original images were reviewed before
the final corrected captures replaced the presentation samples.

The old unified fixture referenced the former session flight button. After that
reference was updated it still pressed G while holding its pickaxe, dropping
the very item needed by subsequent inventory assertions. The flight-key check
now uses empty hands. Diagnostic cursor warps did not fix that failure and were
removed. The terrain check now establishes its aim after cursor capture and
starts with a fresh attack cooldown. Runs with the optional --ground-cover flag
hit cover instead of the intended terrain; the normal invocation above omits
that flag, while the belt check separately exercises vegetation-enabled input.

The first water invocation omitted --water-gameplay and never created its review
lake. The documented invocation includes both water flags and passes. All failed
run logs/manifests remain under retained_failures; none is counted as passing.
An initial export invocation named an absent engine binary; the rebuild used the
same installed executable recorded by the passing test manifests.

The first packed check passed its 34 assertions but failed while trying to save
screenshots into read-only res://. Its failure is retained as pack_readonly_capture.
The fixture now accepts an explicit capture directory; the packed run writes to
its owned report folder and is checked for engine diagnostics as well as assertions.

This UI change does not close the generator, storage cleanup, mining-latency,
world-quality or populated-performance requirements in WORLD_FOUNDATION_STATUS.

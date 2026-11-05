# Pluggable world UI sets

Open **UI sets** from the world browser, or launch
`res://addons/ui_sets/studio.tscn`. Select a set, choose a reference or live-adapter
preview, and switch its page. **Activate set** saves the preference and immediately
opens that set's live world screens. **Back to worlds** exits without changing the
selection. Classic remains the default and is always recoverable.
No world regeneration or saved-world modification is involved.

The original designs remain in their original folders. The studio does not edit
or replace them. Reference previews have input disabled inside a fixed-resolution
SubViewport and cannot trigger world actions. The current shipped UI is itself
previewable using its real view modules and an isolated sample controller mode:
no world-library scan, generation task or photograph job is started.

## Included sets

| Set ID | Preserved reference | Live presentation |
| --- | --- | --- |
| `shipped` | Current browser/create/generation/loading | Original working controls and loading modules |
| `survey` | `demo/world_survey/mockup.tscn` | Photograph beside the library, actual survey left of recipe controls, compact measured loading footer and collapsed diagnostics |
| `expedition` | `demo/world_screens/mockup.tscn` | Planet/library composition, survey and recipe controls, measured loading rail beside the animated planet |
| `diorama` | `demo/world_loading_diorama.tscn` | Animated planet and measured loading rail; inherits the Classic browser/form |
| `campfire` | `demo/world_loading_mockup.tscn` | Photograph, wordmark, campfire tip card and full-width measured loading footer; inherits the Classic browser/form |

All five sets activate through functional presentation modules. Original scenes
remain exact design references. Live compositions use actual library data, recipe
controls and measured progress; reference-only sample metadata and invented stage
counts are not carried into gameplay. These are functional adaptations, not
pixel-identical copies: the library uses the working ItemList, recipe categories
remain tabs, and loading shows the coordinator's actual current stage. The planet
is a decorative portrait, not a visualization of generated terrain. Developer
counters remain available through the ribbon or F1. Designers can replace any
view module while retaining the controller and preserved reference.

## Add a set without editing the registry

Put a folder containing **set.tres** under one of:

- `res://addons/ui_sets/sets/` for bundled sets;
- `res://ui_sets/` for project-local additions;
- `user://ui_sets/` for locally installed sets.

Click **Rescan sets**. Discovery sorts paths, rejects malformed resources and
reports duplicate IDs; an installed set cannot silently replace a bundled ID.
The scan is bounded to four nested directories. Godot resource references retain
export dependencies, so manifests use Script/PackedScene/Font references rather
than paths to resources hidden from the pack exporter.

Create a Resource using `ui_set.gd` and fill these fields:

| Field | Contract |
| --- | --- |
| `schema`, `id`, `title`, `description` | Schema 1; unique lowercase identifier; display text |
| `preview`, `preview_pages`, `preview_size` | PackedScene, 1–16 named pages, bounded reference canvas (default 1920×1080) |
| `base` | Optional set Resource; inherit missing adapters, up to eight acyclic levels |
| `runtime_enabled` | Explicitly permits live activation after validation |
| `runtime_preview`, `runtime_preview_pages` | Isolated live-adapter preview scene and named pages; may be inherited |
| `browser_view` | RefCounted Script, static `build(host:Control)` |
| `creation_view` | RefCounted Script, static `build(host:Control,tabs:TabContainer)` |
| `loading_panel` | PanelContainer Script with the measured loading-panel API |
| `loading_background` | Control Script exposing `picture:TextureRect` |
| `loading_details` | Control Script exposing the diagnostics API |
| `accent`, `background`, `panel_color`, `heading_font`, `body_font` | Optional inputs consumed by the reusable themed adapters |

For a reference-only set, provide identity, description, preview and named pages.
For an inherited working variant, use the Classic manifest as `base`, provide
its preview, enable runtime and override only the scripts you want to change.
See the `survey/set.tres` and `expedition/set.tres` manifests for complete examples.
Preview scenes may implement `show_screen(index)` and `set_mock_time(seconds)`;
the gallery calls only these optional presentation methods. Page names are data,
not a set-name switch in the gallery.

## Runtime ownership

`registry.active()` resolves the selected set. All production browser creation,
embedded generation, generation overlays, Last World cover and gameplay loading
use the resolved presentation adapters. The browser controller still owns saved
slots, recipes, picking and async job state. The generation coordinator, native
workers and terrain readiness still own progress and the release of player input.
A UI module never invents completion to make an animation finish.

The Classic browser module in `sets/shipped/browser.gd` binds all existing host
fields (`worlds`, saved-detail controls, filter/sort, recipe controls, preview,
preparation actions, notice, gameplay and credits). Alternate full layouts must
provide those bindings and connect actions to host methods. The creation view
binds the existing `world_creation_panel.gd` fields/semantics; its recipe helpers
remain authoritative. Editorial adapters compose those controls in the Survey/Planet layouts rather
than copying generation logic. `design_canvas.gd` fits the composition to the
window; library facts scroll when longer than their available space.

Loading panels retain `reset`, `show_progress`, `show_work`, `show_idle`,
`stop_timer`, `timing_snapshot`, `set_compact_width`; fields include `title`,
`detail`, `bar`, `action`, `work`, `embedded`, `preferences_path`. Details retain
`observe`, `reset`, `refresh`, plus `provider`, `context` and diagnostic controls.
The existing host owns cancellation, errors, counters, photographs and ETA.
`registry.create(role)` tags nodes with their resolved `ui_set` resource before
`_ready`, which provides style inputs without a global set-ID switch.

Preferences live in `user://ui_sets.cfg`, independent of world saves and graphics
settings. Selection persists only after explicit activation. Removing or breaking
an active set falls back to Classic. `--ui-set=survey` is a session-only override;
a process-local activation wins when changing sets in the studio. Source and PCK
use the same resource contract. A newly installed custom script is ordinary local
Godot code; the preview isolation is about UI actions, not a code sandbox.

## Verification

- `python TerraForest/tools/check_ui_sets.py`: registry, inheritance, isolated previews, actual GUI activation clicks and scene transitions for all five sets, layout bindings, fallback and measured progress.
- Add `--flow`: actual browser/open/save/reopen/return and photographs with Survey active.
- Add `--loading`: live loading/counters/diagnostics and layout with Survey active.
- Add `--pack` for the current exported executable/PCK.

[Issue and retained evidence](../../issues/modular-world-ui/README.md) track exact
receipts, art-port limits and remaining player review. Scope is world screens;
in-game HUD, inventory and menus are not migrated by this change.

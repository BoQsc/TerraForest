# World-flow mockups (presentation only)

Three screens re-specified from the shipped browser, kept as design mockups for
now. Nothing here is wired into `demo/worlds.tscn`, the world library, the
generation coordinator or the loading panel; no save, world or photograph is
written.

Run the review shell and switch with `1` / `2` / `3` (or the bottom tabs):

```
godot --path TerraForest res://demo/world_survey/mockup.tscn
```

Capture one 1920x1080 still per screen:

```
godot --windowed --resolution 1920x1080 --rendering-method forward_plus \
      --script res://tools/preview_world_survey.gd
```

Recapture the survey map from the game's planner (rewrites
`demo/world_survey/assets/survey_map.png` and prints the plan figures):

```
godot --headless --path TerraForest --script res://tools/capture_survey_map.gd
```

## Screens and their sources

| Screen | Source of truth | What is real | What is representative |
| --- | --- | --- | --- |
| My worlds (`worlds.gd`) | `demo/worlds.gd`, `demo/world_library.gd`, `addons/world_runtime/world_presentation.gd` | Saved slots read from `user://worlds` (currently Amber_Bay, Bright_Forest, Calm_Haven), `presentation.json` seed/generator/options, generator -> landscape names, `.trw` modification time as "Last saved", each world's `.preview/north|road|market.png` photographs, sort/filter and browser actions | Selection is static; buttons do not launch or refresh |
| Create world + generation (`create.gd`) | `demo/world_creation_panel.gd`, `addons/world_runtime/progress_meter.gd`, `world_generation_plan.gd` | Recipe names and descriptions, landscape/settlement option labels, building-grid fit, survey legend and status copy; the survey image is the game's own 256 x 256 plan render captured with `world_generation_plan.preview()` (seed 2, generator 29, frontier recipe) together with its real plan figures - 15 buildings, 1.23 km regional roads, 1.12 km trails, 2 settlements / 2 districts | Stage counters, elapsed/remaining and work string for the generation panel; the plan figures are fixed to that captured plan |
| Loading (`loading.gd`) | `addons/world_runtime/progress_meter.gd`, `loading_panel.gd`, `loading_details.gd` | Loading stage names and captions, the 0/15/20-75/75 stops, "final 6% belongs to playback", coverage/probe/work counters format; the measured card is docked near the bottom at the panel's own 1120 px compact width and 24 px offset; the developer console is collapsed to a single status ribbon at the top edge with an F1 expand hint | The specific counters and timings, which the game reports live at runtime; the expanded developer overlay is not drawn |

## Status

Mockups for review. Adopting any of this means porting the layout onto the real
callers above and replacing the representative values with live signals; that
work has not been started.

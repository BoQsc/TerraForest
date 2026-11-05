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

## Screens and their sources

| Screen | Source of truth | What is real | What is representative |
| --- | --- | --- | --- |
| My worlds (`worlds.gd`) | `demo/worlds.gd`, `demo/world_library.gd`, `addons/world_runtime/world_presentation.gd` | Saved slots read from `user://worlds` (currently Amber_Bay, Bright_Forest, Calm_Haven), `presentation.json` seed/generator/options, generator -> landscape names, `.trw` modification time as "Last saved", each world's `.preview/north|road|market.png` photographs, sort/filter and browser actions | Selection is static; buttons do not launch or refresh |
| Create world + generation (`create.gd`) | `demo/world_creation_panel.gd`, `addons/world_runtime/progress_meter.gd` | Recipe names and descriptions, landscape/settlement option labels, building-grid fit, survey legend and status copy, real generation stage name spanning 42-62% in `progress_meter.gd` | Stage counters, elapsed/remaining, work string; the survey shows a world photograph because the in-process plan render is not available as a file |
| Loading (`loading.gd`) | `addons/world_runtime/progress_meter.gd`, `loading_panel.gd`, `loading_details.gd` | Loading stage names and captions, the 0/15/20-75/75 stops, "final 6% belongs to playback", coverage/probe/work counters format, the developer readout layout | The specific counters and timings, which the game reports live at runtime |

## Status

Mockups for review. Adopting any of this means porting the layout onto the real
callers above and replacing the representative values with live signals; that
work has not been started.

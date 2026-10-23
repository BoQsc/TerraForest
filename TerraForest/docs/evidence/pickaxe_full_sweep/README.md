# Rejected full-sweep experiment

On 2026-10-23 the user rejected this separate animation copy as a complete
regression. The earlier reduced-twist v4 remains the current, uncommitted
candidate. It is not yet approved for commit or synchronization.

The experiment translated the pickaxe across the view while holding its tool
orientation fixed during frames 26–46. That implementation did not satisfy the
visual request. Successful authoring/import does not change the rejection.
`review/` preserves the rendered stills and import report. No final video or
new gameplay validation was completed before the rejection.

`rejected_snapshot/` preserves the eight experimental source, exported asset,
runtime library and tool files under their original project-relative paths.
They were moved out of the character addon and active tools; `.gdignore` keeps
the evidence archive out of Godot's resource import. The archived scripts are
historical snapshots, not active rebuild commands.

`baseline_preserved.json` records the eleven kept v4 files before the experiment.
`baseline_verification.json` confirms every hash still matches after archiving.
The game's controller still selects `FP_Pickaxe_Diagonal_*` and never loaded
`FP_Pickaxe_FullSweep_*`; that library was injected only into the preview scene.

The broader swing without leftward twist remains an unresolved request. Any
future revision must start from the kept v4 candidate and be reviewed visually.
Nothing was staged, committed, merged or synchronized for this experiment.

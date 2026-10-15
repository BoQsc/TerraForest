# Settlement editor presets — 2026-10-15

The existing authoring dialog now exposes cottage and mixed neighborhood presets,
an in-dialog name, ordinary click-to-toggle source selection, and next-step
instructions. It can be opened from single-block selection. Custom numeric
settings and source combinations remain available. Missing required catalog
assets disable the corresponding preset. Invalid empty source selection keeps
the dialog open and displays feedback; valid requests close it.

`settlement_presets.gd` invokes actual button signals, passes the emitted request
to NativeBlockPrefab.compose_settlement and checks the resulting 6,771 cells and
263 model attachments against the independently saved mixed review. It checks
cottage preset replacement and invalid selection handling. `frontage_editor.gd`
also passes, preserving custom single-street and mixed-source requests, max uint
seed and inactive-panel behavior. These are UI signal checks, not OS mouse tests.
The 1920×1080 dialog image was inspected; no performance claim is made.

Generation still uses the existing native path; this change adds no per-frame
world work. Terrain grading/placement is deliberately a separate reviewed step,
and this test does not rerun the existing world placement/save qualification.

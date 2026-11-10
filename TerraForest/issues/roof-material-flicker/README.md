# Roof material flicker

- Status: Fixed for reproduced shader case; normal-world movement review pending.
- Updated: 2026-11-10. Fix: native building material shader, accompanying focused commit.
- User review: Not reviewed.
- Symptom: Zinc roof develops moving speckles while the player moves.

## Changes and verification

The shader interpolated the categorical material code from UV2, then compared
the result exactly with 9 to select zinc roughness/metallicity. Roundoff near 9
switched pixels to non-metal shading. Round the code once in the vertex stage
and pass it flat to the fragment stage, including the joint flag. Textures,
filtering, UVs, geometry, collision, limits and material constants are unchanged.

`tests/roof_material_stability.gd` uses the actual native material with a zinc
quad, roundoff-sized material-code perturbations and eight camera positions.
It compares against the same shader with an exact zinc layer and rejects blank
background comparisons. Baseline failed all eight views (125,182–161,629
different pixels); candidate has zero differences in all eight. This is a
targeted categorical-shading regression, not a normal-world FPS test.

- Baseline: `reports/checks/20261110T133532774772Z_roof_baseline_roi`.
- Candidate: `reports/checks/20261110T133647824922Z_roof_candidate`.
- Thin roof: `reports/checks/20261110T133709857318Z`: 19 checks pass.
- Editor import: `reports/checks/20261110T133748403604Z_roof_import`.
- Installed PCK/libraries, Godot test runtime:
  `reports/checks/20261110T134037658464Z_roof_pack_engine`: all eight views pass.
  This checks the installed package with the editor runtime, not the exported
  executable's restricted external-script interface.
- Structures-only installation receipt: `reports/checks/20261110T133814380498Z_roof_install`.
  Game was closed; debug/release hashes verified. PCK and other native systems
  remain at their previous installed versions.

## Images

![Baseline speckles](../../reports/checks/20261110T133532774772Z_roof_baseline_roi/roof_actual.png)

Baseline: isolated zinc quad, camera step 0, actual native shader, Vulkan
Forward+, RTX 4050, 1920×1080. Artificial roundoff stress; no saved world.

![Corrected zinc shading](../../reports/checks/20261110T133647824922Z_roof_candidate/roof_actual.png)

Candidate: same fixture and view. Inspected against the exact-zinc reference;
texture detail is retained while unstable material classification is removed.
Image hashes/provenance are in `images/manifest.json`; originals remain in the
bounded check reports instead of creating another copy.

## Remaining / resume here

Revisit the reported roof in normal gameplay and move/turn past it when
foreground testing resumes. Confirm no remaining flicker from other causes
(overlap, shadows or LOD). User visual approval remains open. This shader fix
does not close the separate FPS or explosion-publication milestones.

## Reproduce / history

Run `python tools/run_godot_check.py roof_material_stability --require failures=0`.
This is a rendered check; it does not need or write a saved world. Current
investigation used offscreen, nonactivating windows to honor deferred foreground
testing. Exact commands are retained in each report's `run.json`.

The earlier `20261110T133239618694Z_roof_baseline` result is invalid: its
fixed-pixel comparison sampled background after project policy enlarged the
viewport. The corrected comparison uses actual image dimensions and checks
non-background coverage. Preserve that rejected result as test-development evidence.
The first installed launcher (`20261110T133841177335Z_roof_installed`) was rejected
by the export's disabled `--path` override before rendering; it is not shader evidence.
The retry (`20261110T133915779476Z_roof_installed_retry`) likewise rejects
`--main-pack`. Both launcher failures remain preserved. The subsequent Godot
runtime/package check passes without altering export restrictions.

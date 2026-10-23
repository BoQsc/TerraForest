# Terrain-fill placement-feedback correction

The reported gesture failure came from the test fixture, not an accepted edit
losing its animation. `BrushStroke.push_cube()` captures a sample; it does not
authorize or submit native terrain changes. The world uses `TerrainWorld.edit()`,
whose admission hook is owned by `MiningRewards`. In gameplay that hook permits
only excavation brushes and intentionally rejects free fills and grading.

The old fixture changed `construction_inventory.gameplay` for building placement
without changing `mining_rewards.enabled`, which was initialized independently
when the world opened. Its queued fill was therefore refused before native
submission. The presentation correctly stayed idle. Temporary instrumentation
confirmed a nonempty captured addition with no native edit ticket/pending work;
inspection of the admission hook identified the rejection. Diagnostic source
changes were removed; production code is unchanged.

`tests/human_placement.gd` now exercises the actual world in both admission modes:

- Gameplay fill is queued, rejected by the excavation-only policy, and leaves
  terrain edit ticket/revision and the empty-hand idle unchanged.
- Editor cube fill is queued and submitted through `_consume_stroke()`, starts
  the gesture, reaches native publication with a new density revision, and
  returns to empty-hand idle.
- Editor brush fill likewise starts its gesture and publishes; an unfinished
  gesture cannot be restarted. The prior gameplay policy is restored afterward.

Both headless and rendered world runs passed all 42 assertions, including the
selected pickaxe/ready and relaxed-placement lifecycle checks. Logs/provenance
are retained in `checks/`. The rendered run uses an isolated temporary world,
derived cache and off-screen 1920×1080 window. `accepted_editor_fill.png` and
`returned_idle.png` were inspected: the accepted action displays the relaxed low
hand, and the hand lowers out of view afterward. The temporary fixture's
authored block is not a world-content change. These are functional/presentation
checks, not general terrain-performance or animation-quality acceptance.

No gameplay permission, mining reward/cadence, native world-edit code, animation
asset or user-save change is required. Earlier failures remain in
`../pickaxe_integration/checks/placement_open_failure/` for history.

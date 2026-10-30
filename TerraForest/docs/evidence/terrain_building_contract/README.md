# Shared terrain/building correction evidence

All tests ran in the isolated trader/civic worktree. Reports retain commands,
revision/dirty state, test and native binary hashes, exit status and diagnostics.
Old failures remain visible. No player save was used as a destructive fixture.

| Evidence | Meaning |
| --- | --- |
| `catalog_before` | Original missing surface gate: ten catalog failures |
| `quarter_metre_trial_city`, `quarter_metre_trial_house` | Rejected global 0.25 m soil offset; damaged legacy support/fit |
| `narrow_mask_before` | Three remaining narrow-stair failures; led to preserving the vertical subtractive plane at covered mask edges |
| `catalog_after` | 64 passing checks: 46 civic/city/neighborhood buildings and six sidewalk sets, seeds 1703 and 42 |
| `contract_after` | Initial 29-check source contract pass |
| `final_export_gate` | Final 30-check debug and release contract, including actual footprint versus attachment envelope; 64 catalog checks |
| `complete_generation` | Production opt-in civic generation/publication succeeds |
| `large_house` | 56 checks preserve the approved large house and actual capsule traversal |
| `world_portico_goal`, `npc_interior_budget_before`, `npc_trace_budget_before` | Retained NPC failures: initial suspicion of oscillation was disproved by the trace. The NPC advanced steadily along a 49.4 m route; the fixed 25 s test deadline was too short at 1.6 m/s. |
| `envelope_regression_before`, `envelope_regression_after` | Planner formerly accepted an elevated cell inside a stale ground-reaching attachment envelope; it now requires a native grounded footprint |
| `footprint_fixture_before`, `footprint_fixture_after` | Old cottage assertion expected 396 columns, predating six approved approach-support columns per cottage; exact expected count is now 420 |
| `grading_regression_before`, `noop_harness_before` | All assertions passed but the runner expected a missing completion marker; tests now emit an explicit summary |
| `grading_regression_after`, `noop_regression_after`, `site_fit_after`, `terrain_lot_after` | Passing affected grading, repeated preparation, survey and planner regressions |

The route test now sets one bounded deadline from the published native path length
and real speed, with five seconds of margin and a 6,000-tick absolute cap. Replans
cannot extend it. Arrival tolerance, physical movement, route work and collision
checks remain unchanged. The final integrated route evidence is in
[the civic world evidence](../civic_buildings/world/README.md).

The earlier `coplanar_fixture` failure used exact float equality in a rejected test
fixture; it is not a passing implementation result. Logs and captures remain
unmodified, including their original paths. New code is 0BSD; no third-party
implementation or texture was imported for this correction.

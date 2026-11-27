# Extensive lakes

Source update, 2026-11-27. The request is for several substantially longer lakes
within the inhabited-region recipe. New worlds select terrain IDs 32–35; IDs
1–31 and existing saved terrain remain unchanged. Ocean and buildable-ground
choices remain independent. Treat IDs 32–35 as immutable from this change onward;
future landscape revisions need new IDs. The installed export has not been rebuilt.

## Shape and placement

Three long basins share the map with up to six smaller lakes/ponds. Seed 1703 measures
**478 m, 418 m and 362 m** of connected wet surface at 2 m survey resolution,
including after the city and roads are baked. The earlier largest lake measured
190–196 m. Seeds 0, 42, 1703 and 9137 across all four new terrain profiles have
three connected lakes longer than 330 m. These are finite, level water bodies.

Native candidate searches survey the full long footprint and reserve separate
axis-aligned envelopes around settlements, caves and other lakes. The long
basins have different lengths and shapes. The two-lobed basin has a wider neck
so its connection remains legible at regional map resolution. Ordinary custom
planning rejects a landscape that cannot fit three connected long lakes.

Each long lake occupies three adjacent catalog sections. Those sections share
one water level and the existing regional water store; they are not fifteen
separate physical lakes. Nine basins use at most fifteen catalog records, each
within the existing size bounds. Even-aligned boundaries preserve the 2 m map
survey lattice. Actual water retains the existing 0.5 m volume resolution.
The native 128 MiB bake-state and 64 MiB snapshot caps remain unchanged.

The city still requires all 84 buildings, its three grand landmarks, six outlying
communities and two large plus one small bridge. The new layout also exposed
shared sidewalk cells between adjacent city quarters. Native recipe processing
keeps the first owner of identical paving cells and rejects conflicting blocks;
it does not overwrite building or bridge cells. All cells remain separately
destructible. The binary recipe format is unchanged; derived plans use v58.

## Verification and acceptance

- `tests/extensive_lakes.gd`: 62 frozen legacy terrain/catalog fingerprints;
  sixteen new seed/profile surveys; closed physical shores; unchanged water
  allocation caps; restored water at all six internal catalog seams.
- The water decoder may add pending-settlement flags for rounded boundary cells.
  The check permits only that existing flag transition and compares every other
  byte, including quantities and contacts. A second canonical reopen must match
  byte for byte. It also checks safe shared-paving ownership and conflict rejection.
- `tests/metropolis_recipe.gd`: full final-field contact checks, required content,
  normal browser/map preview, and native publication of all building, bridge and
  paving cells together.
- Ordinary Create world → Metropolis & inhabited region → Generate & play,
  publication, construction catalog, trader interaction and fresh-process
  restoration completed **6 / 73 / 30 functional assertions**, including real
  water and published render owners at all three lakes:
  `reports/metropolis_world/20261127T163022033235Z/run.json`.
  `functional_passed` is true; strict `passed` is false. Creation/restoration
  reproduced the inherited zero-reference ObjectDB exit warning. The explicit
  diagnostic-continuation option preserves those failed phase results and the
  overall nonzero exit; it cannot turn failed assertions or live references into
  a pass. Earlier ordinary run `20261127T155854827214Z` passed creation and
  interaction cleanly, with the same cleanup warning after restoration.
- The corrected low view confirms the extended, continuous water surface.
  A high aerial view remains rejected as full-lake rendering evidence: the
  surface is not completely visible there. Distance/LOD/overview coverage needs
  separate investigation and repeatable full-extent views before acceptance.


Whole-world visual acceptance, long bank walks, populated-world frame pacing and
weak hardware remain unqualified. Short native bake timings do not establish
playable-world performance. Older installed-build evidence remains in
[the lake issue](../issues/lakes-and-bridges/README.md); the new source profile
must not be described as an installed-build qualification.

## Retained trials

The original narrow-neck map is retained in
`reports/checks/20261127T152528453244Z`; the wider-neck map is in
`reports/checks/20261127T153513621642Z`. Early persistence assertions incorrectly
required decoder settlement flags to remain unchanged; failed receipts remain in
`20261127T151845815083Z`, `20261127T152027648246Z` and `20261127T152150943508Z`.

The first ordinary creation caught duplicate sidewalk publication:
`reports/metropolis_world/20261127T153715786076Z`. Its failed staging fixture was
cold-retained by its receipt (54,417,813 bytes); player saves were not selected.
The native cell audit reproduced 119 identical overlapping paving cells at the
Needle Street quarter (`reports/checks/20261127T154344714234Z`).

The older three-seed bridge-plan check timed out at 180 seconds while run beside
other source checks (`reports/checks/20261127T153105791724Z`), after its prefab
rotations and seed-0 plan passed; its dummy-renderer material diagnostics remain
visible. That full legacy check is not claimed as passed. Its older random
`lake_plan_*` cache paths are outside this run's managed temporary-cache receipt
and have been retained, not removed by name.

Later creation checks completed all six assertions but reproduced that exit
warning (`reports/metropolis_world/20261127T155107956653Z` and
`20261127T161928049376Z`). Their owned fixtures were cold-retained. A fresh-frame
quit helper does not establish a universal lifetime fix. Closure still requires
repeatable clean native exits; keep this separate from lake geometry/persistence.

The first lake-view capture paused player physics before streaming focus followed
the completed teleport. Those images are rejected as water-render evidence. The
capture helper now keeps focus on the paused player's actual position, waits for
the lake's real render owner, and hides the first-person tool. Shader, fog and
world content remain ordinary source settings.

The older three-seed bridge check should be rerun after its random cache paths
have a bounded, receipt-owned lifecycle. Closure requires all three seeds to
finish with clean diagnostics under an adequate declared timeout; its partial
result is not a substitute for that full regression.

Final owned-fixture retirement is recorded in the production report's
`retention.json` and `world.archive.json` (77,737,140 bytes). Only its staging and
published test world were selected. Existing player saves remain protected.
The temporary QA allowance is process-local; final normal-limit admission is
recorded separately after the launcher exits.

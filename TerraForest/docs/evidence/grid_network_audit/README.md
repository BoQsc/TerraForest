# Saved-road regression: grid preference remains insufficient

2026-10-25; revision eabcb85c. This is diagnostic evidence, not a generation fix.
The user saved and closed the isolated review world at the reported problem area.
`tools/audit_grid_network.py` loads it read-only in a temporary offscreen session;
its process report verifies both this save and Wild_Hills remain byte-identical.

## Actual collision and planner agreement

- Save: GridPreference_1703_f3de49d9, seed 1703, generator 23, road preference on.
- Saved player position: (1074.4521, 47.2111, 842.4988).
- Ordinary brick target: (1076, 47, 838), green/allowed, burial **42.30 cm**.
- Nine physics heights: 47.3756–47.4230 m; gap zero at base 47.
- Base 48 would instead leave about 62.44 cm of air. Neither choice meets the
  provisional 10 cm gap / 25 cm embedding contract.
- Planned road height at the aim point: 47.40881 m; actual collision 47.40873 m.
  The mesh correctly represents the bad generated grade.
- Segment: (1088,49.1879,800) to (1056,44.6812,896), asphalt half-width 4 m.
  It retained its original linear profile. Calling the production normalizer
  on this road and the real protected areas gives `changed=0`,
  `earthwork_skips=1`, `ok=true`. The metadata `grid_normalized=true` means the
  option was processed, not that this road was actually corrected.

## Broader screening

At each tested one-metre footprint, the analytic test asks whether *any* integer
base can keep both limits, independent of the targeting preference. Nine samples
use the same footprint offsets as the contact checks. Original and normalized
profiles are compared at identical grid coordinates along both settlement and
regional road segments; nearest centerline selects overlapping profiles.

| Category | Sampled footprints | Unfit before | Unfit after |
| --- | ---: | ---: | ---: |
| Settlement streets | 769 | 265 | 227 |
| Regional roads | 1,268 | 871 | 782 |
| Total | 2,037 | 1,136 | 1,009 |

This covers the network's planned profiles, not every terrain cell or final road
mesh. Curved caps, junction unions, shoulders and later stamp interactions need
additional baked collision evidence. Subdivision increases the number of reported
endpoints; do not compare raw endpoint counts as an improvement/regression metric.
The saved problem target itself is measured against actual loaded collision.

`result.json` includes exact measurements, parameters and nearby road descriptor.
`run.json` records command, revision and unchanged-save checks. `saved_problem.png`
shows the saved area after inspection; it is not an edited image or an assertion
that the camera exactly matches the user's earlier screenshot.

## Meaning of the result

Audit capture passes; **world quality is rejected**. The normalizer currently
checks shape/earthwork constraints, not the requested world-wide building-fit
contract. A two-location pass did not establish broad quality. Changing only the
placement choice cannot fix this road; lengthening a slope does not remove its
fractional elevations either. Do not publish another local success as completion.

This commit changes only regression diagnostics and documentation. It leaves
generation, the user's saves, building freedom, approved houses and plates intact.
The remaining generation strategy and acceptance gates are tracked at the top of
`WORLD_FOUNDATION_STATUS.md`.

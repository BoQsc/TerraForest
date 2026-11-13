# Player shoreline, teleport and contact repair

Functional repair is installed and verified in the actual game. The repair
checklist in [the plan](water-plan.md) is complete. Performance soft targets are
not universally met; the remaining work below stays open. User visual approval
is separate from these programmatic checks and agent image inspection.

## Causes and implementation

- A visible surrounding shoreline could lie outside the player-centered native
  ocean patch. Barrels now prepare bounded coastal occupancy before terrain
  changes; the existing detonation queue retries while preparation completes.
- Equilibrium snapshots retained every resident region and prior occupancy.
  They now retain affected connected groups and their frontier. Unrelated pools
  are excluded, and pending groups outside a transaction remain pending.
- The surrounding procedural sea uses its existing open, level-40 reservoir
  boundary. Actual clipped 3D connections control admission; sealed pockets
  remain finite. Net reservoir exchange is explicit. Inland lakes retain exact
  finite quantities. Neither memory nor traversal limits were raised.
- Averaging surface crossings beveled water away from construction walls.
  A bounded Hermite fit preserves the solid/free-surface intersection while
  retaining shared topology. Sharp contact normals no longer blend into a rim.
- Deposited terrain had a separate mismatch: the rendered top was 47.25 m,
  while the fallback water occupancy extended to about 47.65 m. Its narrow-band
  occupancy now comes from the exact terrain boundary packet already used for
  contact. Version 13 refreshes older occupancy caches without deleting amounts.

## Evidence and rejected runs

All IDs refer to `reports/checks/<ID>/`. Full logs, hashes, telemetry and capture
ownership stay there. Older PNGs may be cold-retained through `captures.archive.json`.
The checks use the game scene and real combat/terrain/inventory transactions.
Rendered runs use an owned non-input Windows desktop, with no desktop switching
or input injection. Player-world checks load Amber_Pines read-only and verify
the canonical save hash afterward.

- `20261113T191120333310Z`: rejected; once shoreline pre-admission exposed the
  real edit, the old finite solver exceeded its connected-body work budget.
- `20261113T191813659627Z`: 4,096 unrelated pools retain exact quantities while
  a local snapshot remains small. `20261113T191922672079Z`: open ocean exchange,
  sealed pocket and missing-boundary finite behavior pass.
- `20261113T191922665005Z`: read-only player-world shoreline explosion fills
  the crater; subsequent lake teleport completes. Save hash is unchanged.
- `20261113T193046437758Z`: rejected contact fixture placed its cube using a
  ray through the terrain deposit. The fixture now uses undisturbed water and
  asserts the cube actually crosses the current free surface.
- `20261113T193733907948Z` and `20261113T193909193007Z`: rejected; ten deposited
  terrain coverage probes exposed the occupancy/render mismatch.
- `20261113T194258663075Z`: visible gap and coverage repaired, but six unmatched
  mesh edges rejected broad terrain-contact fitting. Terrain now uses corrected
  occupancy with the existing shared extractor; the sharp fit stays local to
  solid clipping contacts.
- `20261113T194557718267Z`: full source game passes five barrels, mining,
  deposition, exact finite conservation, snapshot reload, unfinished-save
  recovery, legacy-cache migration, closed nondegenerate seams and cube contact.
  All submerged deposit probes pass. Captures above and below water inspected.
  Primary publication is 245.198 ms after terrain publication. Moving combat
  p95/p99/max is 9.375/11.618/14.931 ms; water main maximum 986 us. Repeated
  water-on GPU p95 is 6.301/6.340 ms versus 4.864 ms off, at 1920×1080 on the
  RTX 4050 laptop GPU. These are scoped measurements, not universal bounds.
- `20261113T194812120477Z`: rejected before gameplay; version-13 migration
  initially changed the reconstructed version-12 checkpoint's canonical hash.
  The save remained unchanged. The decoder/encoder now retain the prior cache
  revision until terrain resampling actually upgrades it; explicit version-12
  and version-13 generated-checkpoint roundtrips guard this compatibility path.
- `20261113T195202051402Z` / `20261113T195202104662Z`: rejected archive and
  streaming regressions distinguished byte-preserving archive expansion from
  runtime geometry migration. Current-cache fixtures were also advanced to v13.
  Final checks `20261113T195514197161Z` (old/new generated and edited snapshots),
  `20261113T195514183721Z` (production streaming save/reopen) and
  `20261113T195514174800Z` (mesh worker lifetime/publication/migration) pass.
  Finite equilibrium, ocean exchange, 4,096-pool scope, 510 continuity patterns
  and contact volume pass in the `20261113T195202*` batch.
- `20261113T195539770428Z`: rendered Amber_Pines sequence passes coastal blast,
  lake teleport, lake blast and moving combat, with unchanged canonical save.
  The first timing pass exposed repeated stable ocean-residency work. Residency
  now reruns on movement/change, with a bounded periodic expiry pass. Publication
  diagnostics distinguish scene-node, native-query and ocean-mask costs.
- `20261113T195813515579Z`: rejected global-total assertion counted retiring
  pristine ocean water as finite owned mass. The driver now compares the
  production save snapshot's non-regenerable total around the inland lake blast.
- `20261113T201311416531Z`: repeated shoreline edits exposed discarded vacancy
  records. The worker commit now retains the ocean vacancy channel. The final
  debug/release checks in `reports/water_patch/20261113T201905071144Z/` pass
  14 ocean-boundary/vacancy assertions and five scoped-snapshot assertions each.
- Native storage/transfer/reset coverage is split across retained reruns:
  `reports/water_patch/20261113T200848746070Z/` passes through region transfer
  in both builds, then rejects an obsolete version-10 assertion. Corrected
  residency and snapshot-cost checks pass in `20261113T201611917054Z`; its
  test-only eager game-scene dependency is removed for the final native-only
  ocean/scope run above. Failed DLL copies remain hash-verifiable in each run's
  `native.archive.json`, with all logs/fixtures retained.

Earlier primary-publication samples of 309–377 ms and occasional main-thread
soft-budget overruns remain in the retained reports; the 250 ms target is not
a hard deadline. No full fluid dynamics or arbitrary sub-cell film guarantee
is claimed. User visual approval remains separate from agent inspection.


Runtime and regression commit: `97b8cf6b`. [Installed hashes and final telemetry](water-repair-verification-2026-11-13.json).

## Final installed-game verification

- `20261113T202109755027Z`: five actual barrels, shoreline breach, mining,
  paid deposition, finite conservation, snapshot/reload, unfinished-save recovery,
  legacy migration, closed nondegenerate boundary and four 1 cm cube-wall probes
  pass. Submerged terrain coverage passes; above-water block and deposited-terrain
  captures were inspected without the prior dry gap. Primary water publication
  takes 275.010 ms after terrain; primary main work peaks at 0.962 ms.
- `20261113T202313670116Z`: existing Amber_Pines loaded read-only, coastal barrel
  fills excavated space, lake teleport completes without the memory failure,
  lake barrel fills below the former floor with exact owned snapshot quantity,
  and all three moving-combat barrels detonate and finish water publication.
  Original player-save hash is unchanged. Six captures inspected. The coastal
  underwater camera is beneath terrain and is rejected as visual evidence;
  the lake underwater image correctly shows the flooded excavation.
- Native debug/release binaries match the checked source and installed package.
  `reports/water_repair_export_final.log` records all nine required building
  contracts, export, packaged startup and house-light checks passing.
  `reports/worlds_launch.json` records the source and both native hashes after
  successful native Godot launcher preparation. Both desktop shortcuts target
  that bootstrap; Last World propagates Continue. No editor window is required.

Final 1920x1080 moving-camera measurements (milliseconds; 210 sampled frames
per phase, uncapped rendering on the existing RTX 4050 laptop GPU):

| Installed run / phase | Frame p95 | Frame p99 | Frame max | GPU p95 | Water main max |
| --- | ---: | ---: | ---: | ---: | ---: |
| Controlled combat | 12.970 | 17.500 | 21.667 | 7.984 | 1.384 |
| Amber_Pines water off | 12.723 | 14.390 | 16.037 | 5.294 | 0.914 |
| Amber_Pines water on A | 15.029 | 16.759 | 17.202 | 8.220 | 1.310 |
| Amber_Pines water on B | 13.060 | 14.908 | 17.551 | 8.796 | 0.779 |
| Amber_Pines combat | 16.318 | 18.691 | 21.393 | 10.053 | 2.141 |

Water-main values in this table cover the measured moving phases, not startup
or every publication. The full saved-world sequence records mesh-publication
peaks of 13.226 ms (1,017 meshes in the reported batch, dominated by scene-node
work), and a connected equilibrium worker transaction of 3.622 seconds. That
worker time is asynchronous, not a main-thread frame duration. The 24 FPS HUD
in the coastal post-blast capture is not discarded or presented as a 60 FPS pass.

Remaining performance work: reduce large scene-mesh publication batches and
connected-body worker latency without publishing partial water/terrain states.
The measured overruns are the return trigger, not a claim that the 250 ms / 1 ms /
16.7 ms targets were achieved. Closure requires repeatable moving-camera traces,
including coast/lake edits and on/off GPU samples, with those targets met. This
follow-up is separate from the repaired loading, missing shoreline response and
contact failures; no functional rollout or save migration is deferred.

Agent-inspected final images (original game renders, no image synthesis):

- Existing coast: [before](../../reports/checks/20261113T202313670116Z/player_shore_before.png),
  [flooded barrel crater](../../reports/checks/20261113T202313670116Z/player_shore_after.png).
- Existing lake: [after barrel](../../reports/checks/20261113T202313670116Z/player_lake_after.png),
  [underwater excavation](../../reports/checks/20261113T202313670116Z/player_lake_underwater.png).
- Contact regression: [block](../../reports/checks/20261113T202109755027Z/object_contact_above.png),
  [deposited terrain](../../reports/checks/20261113T202109755027Z/deposition_above.png).

Captures follow receipt-owned retention; archive manifests remain beside the runs
if ready images are subsequently archived. No desktop switching or input injection
was used, and player saves were not rewritten.

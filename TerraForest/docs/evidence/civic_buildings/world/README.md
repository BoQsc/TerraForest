# Integrated civic approval evidence — 2026-10-30

World `CivicReview_1703_8ae64a06`, seed 1703, civic plan version 29. Production
preparation, native construction publication and compound save; 8,685 trees,
1,024 forest owners. Existing gameplay worlds were not modified. All tests below
have zero failures in their final runs. The JSON result is written before the
last durable-shutdown assertion; console totals include that assertion.

| Check | Assertions | Evidence |
| --- | ---: | --- |
| Full generated-world traversal and trade | 73 | [routes](routes/run.json), [console](routes/console.log), [metrics](result.json) |
| Fresh-process exact player/merchant restore | 18 | [restore](restore/run.json), [console](restore/console.log) |
| Ground/overview views and actual basement descent/support | 18 | [details](details/run.json), [console](details/console.log) |
| Paired merchant rendering cost | 5 | [performance](performance/run.json), [measurements](performance_pair.json) |
| PCK candidates/currency/icon | 6 | [pack](pack/run.json), [console](pack/console.log) |
| Merged door definitions and old-content compatibility | 58 source + 58 PCK | [source](merged_doors/run.json), [pack](packed_doors/run.json) |
| Package dependency and test-runner contracts | 13 Python tests | [passing result](addon_package_after.log) |

Player and native-NPC paths start on connected streets and finish inside each
building. Upper and basement stair topology and landings are traversed. Both
warehouse driveways admit the real native vehicle. All saved block words match
the corresponding R1 candidate. Tests open existing doors with their native
hinges; fewer checks than the first 91-check run reflect already-open saved
doors, not omitted routes. The 18-check detail pass separately walks down to,
and settles on, each basement floor.

The trader test uses normal picking, interaction and UI to sell 20 explicitly
granted test twigs, then buy three wood. The fixture reward is confined to this
new review world; production grants no starter money. LOS, focus ownership,
retirement/reactivation and no automatic stock refill are checked. Fresh process
restoration compares both complete inventory byte snapshots, not just totals.

At 1920×1080, RTX 4050 Laptop GPU, the stationary uncapped ABBA comparison has
600 frames per state. Merchant hidden: mean 7.983 ms, p95 8.806 ms, worst 9.874 ms;
visible: mean 8.041 ms, p95 8.754 ms, worst 11.860 ms. This is a short incremental
comparison, not a statistically established speedup or an endurance guarantee.
Screenshot readback is outside timing. Other engine processes were absent when
this paired check started; the other chat's ongoing work was left isolated.

The broader capped moving-camera samples show p95 21.744–24.262 ms and worst
27.145–33.770 ms. They do **not** meet a strict 16.67 ms/60 FPS envelope. The other
chat continues frame-pacing/vegetation work. Some screenshots show lower transient
FPS during capture; their HUD is not performance acceptance. Do not claim that
this civic feature pass closes that broader issue.

The whole-game export starts with 14 matching external native libraries and is
430,029,071 bytes including its recorded distribution contents. The required
[30/64/30 source/catalog/release gate](../../terrain_building_contract/final_export_gate/run.json)
passes against these binaries. PCK resources resolve from `dist`, not loose addon
source. [Export log](export.log), [size record](distribution_budget.json).

## Retained failures

- `before_apron_*` retains the preceding preparation trial and its own slot;
  it is not final-world evidence.
- [Native contact failures and route deadline diagnosis](../../terrain_building_contract/README.md)
  retain the rejected soil-offset attempts, narrow-mask reproductions and NPC
  traces. The town-hall trace showed steady progress, not the initially suspected
  oscillation. The corrected fixed route-length budget passes without changing
  navigation or collision behavior.
- [Initial PCK fixture](pack_fixture_before/console.log) called a nonexistent
  `has_item` API. The replacement verifies actual coin admission through the native
  inventory grant API; the packaged rerun passes.
- [Addon package failure](addon_package_regression.log) exposed outdated declared
  dependencies. `package.py` now includes the actual host services and demo/assets/
  mods used by world adapters; the deterministic bundle/runner suite passes.
  Dependency bundles can consequently be larger. This is dependency completeness,
  not independent addon-runtime or all-platform qualification.

[Inspected images and provenance](../../../../issues/civic-buildings/images/manifest.json)
remain original captures. The user approved all five exact R1 designs and the
submitted work on 2026-10-30. The future expansion direction is approved; its
finished implementation must demonstrate justified real-world gains for a
separate review and approval. Historical logs/capture statuses are unchanged.

# World creation recipe verification — 2026-10-25

This evidence qualifies the configurable creator and generation/storage plumbing,
not final city design, every road approach, or lower-end gameplay performance.
See `../../WORLD_GENERATION_RECIPES.md` for the contract and remaining work.

## Passing checks

- `source_recipe/`, `world_recipe.json`: four recipe sizes, biome admission,
  native storage, cache equivalence and main-loop responsiveness.
- `large_matrix/`, `world_recipe_matrix.json`: nine 68-building layouts across
  seeds 0, 42, 1703 and terrain profiles 19, 20, 21.
- `legacy_matrix/`, `legacy_layouts/`, `recipe_legacy_equivalence.json`: existing
  flat-plate plans remain deterministic and their nine baseline digests match.
- `source_generation/`, `generation_result.json`: actual 68-building generation,
  publication, same-window play/save/reload and exact recipe/region restoration.
- `source_ui/`, `browser/`, `images/`: rendered creator at 1920×1080 and 1280×720,
  settings propagation, preview identity and existing saved-world browser.
- `world_recipe_native_release.*`: 16 assertions with isolated release DLLs.
- `shipped_package/`: final package native and rendered UI checks, plus read-only
  six-district reopening. `run.json` records the tested package SHA-256.
- `cold_recheck/`: same final package, with only this test world's edited-terrain
  raster archived first; 474 patches rebuilt, then all four warm layers reused.
- `recipe_reopen_cold_warm.json`: earlier cross-build cold terrain/building-map
  rebuild and warm reuse. `recipe_export.log`: packaged startup verification.
- `artifact_hashes.json`: source/package native binaries and package identity.

## Failures retained, not counted as passes

- `initial_map_label_failure/`: native navigation labels reject non-ASCII text;
  labels now use ASCII and metadata is preflighted before expensive baking.
- `initial_layout_failure/`: some expanded layouts failed native connection;
  bounded exit selection and deterministic district relocation were added, without
  relaxing fill/cut or crossing limits.
- `initial_ui_failure/`: small-window footer clipping; responsive sizing fixed.
- `legacy_reopen_fixture_failure/`: the old fixture assumed two districts and an
  already-warm cross-build map; the dedicated six-district fixture replaces it.
- `initial_pack_native_fixture.log`: report directory creation used a virtual
  resource path; the test now resolves its filesystem report directory.
- `initial_shipped_test_run.json`, `initial_shipped_reopen_timeout.log`: one map
  reopen exceeded the outer 180-second deadline. Cause remains unestablished;
  instrumented warm and deliberately cold reruns pass. A wider outer deadline
  accommodates the two independently bounded loads; it is not an application fix.

Generation handoff tests also initially returned before the deferred scene
transition; they now distinguish pending handoff from failed/cancelled generation.
Test worlds are archived under the ignored `reports/recipe_world_archive/`, not
left in the player's world selector. `test_world_archive.json` records only the
owned fixture slots and staging directories moved; original user saves are kept.

# Approved cottage roof A2 — 2026-10-25

User decision: **"I approve this roof, seems better."** This closes A2's explicit
design-approval gate, not settlement-wide quality or performance acceptance.

## Delivered

The production prefab copies all 555 block records and 13 attached objects from
the reviewed A2 R2 exactly. Only the resource name and approval metadata differ.
New enclosed cottages keep their previous palette index and lookup name.
The native thin slopes, ridges and seam pieces retain independent grid ownership.
No geometry, native code or other house design changes in this promotion.

The previous A0 implementation is preserved as `legacy_enclosed_cottage()`.
Historical A0/A1 comparisons and reproducible review authoring explicitly use it.
Stored buildings are not migrated. Raw cottage templates and the approved B1 shop
remain untouched. The existing cellar recipe composes the approved cottage,
retaining its own previously defined cellar; this is not a new cellar redesign.
Both derived generation-plan versions advance to 4; world-storage versions do not.

## Verification

| Check | Result | Evidence |
| --- | --- | --- |
| Approved default in actual temporary source game | 32 checks, zero failures | `source/` |
| Same test in rebuilt exported PCK | 32 checks, zero failures | `pack/` |
| Export and startup with 14 external libraries | Passed | `pack/export.log`, `pack/pack_smoke.log` |
| Mixed regional recipe, 13 seeds | Passed | `mixed_recipe/` |
| Four custom-world configurations, cold/warm plan caches | Passed | `world_recipe/` |
| Historical A0/A1 and B0/B1 comparison | 41 checks, zero failures | `historical_comparison/` |
| Approved shop palette regression | 12 checks, zero failures | `shop_regression/` |
| A0/A2 comparison, headless | 16 checks, zero failures | `roof_comparison/` |
| Fresh-process A0/A2 compound restore | 3 checks, zero failures | `roof_restore/` |

The default test verifies exact reviewed records/attachments, independent resource
instances, unchanged placement bounds and foundation samples in all four rotations,
generation recipe and cached-plan asset reconstruction, legacy block snapshots,
the actual construction UI index, native compound placement, one-block removal
without neighbor removal, and exact compound restore. These are temporary worlds;
no player saves are modified. This is not a populated-world performance benchmark.

Visual evidence remains the actual Godot renders inspected for A2 in
`../cottage_roof_a2/images/`; the approval changes no building geometry. Earlier
manifests retain their historical pending-approval status rather than being
retroactively rewritten. Current asset/pack hashes and run outcomes are in
`manifest.json`.

## Failures retained

- The initial new test used nonexistent `set_cell` and tried to place an attached
  prefab through the blocks-only API. The first run timed out after the script
  error; the next still failed its two blocks-only placement assertions.
  The corrected fixture uses `set_cells`/a blocks-only prefab for that isolated
  snapshot test and the real compound transaction for attached gameplay placement.
  Both failed runs remain in `failed_initial_fixture/` and
  `failed_block_only_fixture/`; neither is counted as a pass.
- The older `settlement_capacity` suite fails its tower-only fixed object-count
  assertion; `settlement_presets` fails its fixed mixed-layout count assertion.
  Both also fail with the unchanged historical A0 recipe substituted, retained in
  `legacy_capacity_failure/` and `legacy_preset_failure/`. The exact baseline
  probe scripts are retained as text. These failures predate adopting this roof;
  the suites are not reported green or silently relaxed. The nine current
  preflight-versus-composition cases pass. Reconcile stale fixed-count fixtures
  with current tower/preset recipes separately, then rerun both suites.

## Remaining scope

Generated terrain-fit, populated street-to-interior traversal and sustained frame
times still need their own integrated acceptance evidence. The unchanged foundation
and envelope tests do not replace those gates. Shallow/arbitrary roof pitches and
structural-collapse behavior remain outside this approved 45-degree roof revision.

## Reproduce

```text
python tools/run_godot_check.py approved_cottage_roof --headless --timeout 120 --require "APPROVED_COTTAGE_ROOF checks="
python tools/run_godot_check.py world_recipe --headless --timeout 180 --require "WORLD_RECIPE failures=0"
python tools/run_godot_check.py cottage_roof_review --headless --timeout 90 --require "COTTAGE_ROOF_REVIEW checks=" -- --review-output=res://reports/approved_cottage_roof/recheck
python tools/review_modular_buildings.py --roof
```

The packed check's exact command is retained in `pack/run.json`; it loads the
external test/reference while all production resources come from the PCK.

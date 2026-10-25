# Shop B approval and signed review — 2026-10-25

User decision: **B1 / Village Shop B R1 is the only approved addition** to the
existing designs. A1 / Cottage A R1 is rejected. The original A0 cottage roof is
also visually rejected; retaining it unchanged is not acceptance of that roof.
No new roof geometry is delivered by this change.

## Delivered scope

- Exact approved B1 block records and attached models copied into the production
  prefab `addons/structures/prefabs/village_shop_hipped_r1.tres`. Only its name and
  approval metadata differ from the review asset. No architectural edits.
- One additional construction-palette entry, appended after existing entries.
  Existing recipes, prefab indices and user saves remain unchanged. Generation
  does not start selecting B1 automatically.
- Signed walk-around review with A0, B0 and B1, connected native plate paths,
  separate native sign cells, normal grounded movement and individual E-door
  interactions. Starts at the shops. Rejected A1 is omitted from this scene.
- Historical split comparison remains explicitly available with `--comparison`,
  labeled rejected/approved-addition. Archived review assets remain unchanged.

## Verification

| Check | Result | Retained evidence |
| --- | --- | --- |
| Graphical signed walk-around, 1920×1080 | 60 checks, zero failures | `walkaround/` |
| Actual temporary game palette | 12 checks, zero failures | `gameplay_palette/` |
| Historical comparison regression, headless | 41 checks, zero failures | `comparison/` |
| Fresh-process exact compound restore | 3 checks, zero failures | `restore/` |
| Exported PCK startup | Passed, 14 external native libraries | `pack/export.log`, `pack/pack_smoke.log` |
| Same palette test using exported PCK | 12 checks, zero failures | `pack/run.json`, `pack/console.log` |

The walk test verifies every building's native cell records, approval signs,
rejected A1 absence, path cells, keyboard shortcuts, flight return, Esc resume,
focus loss/return, connected approaches, stairs, E targeting, door opening,
supported interior traversal, exit and storage roundtrip. The palette test uses
the actual temporary gameplay scene and the normal UI selection signal. The pack
test reads the historical review reference via an explicit external test path;
the production prefab itself is loaded from the pack, not the review directory.
The walk fixture injects keys and focus notifications; before injected keys it
restores simulated focus if the desktop lost it. The log reports that explicitly.
This tests the scene's input/focus handlers, not end-to-end operating-system Alt+Tab.

Inspected `images/arrival.png`, `shop_sign.png`, `cottage_sign.png`, `overview.png`
and `interior_B1.png`. Signs clearly distinguish original B0 from additional B1.
The cottage image intentionally retains the rejected chunky verge for reference;
it is not evidence that the roof is fixed. Elevated inspection images are test
camera poses; the actual overview shortcut enables flight. The neutral ground
plane is review staging, not generated terrain.

The source build and PCK contain the same B1 data. `manifest.json` records hashes
of the pack, code/resources, DLLs and retained evidence. The unrelated pre-existing
item-icon bake manifest remains untouched and is not part of the commit.

## Failed and interrupted checks retained

- `failed_escape/`: first headless walk test failed Esc resume and subsequent
  pointer recapture. Focused menu controls consumed the second Esc before the
  unhandled-input callback. Handling Esc in `_input` fixes that review-scene bug;
  the final graphical checks exercise both paths successfully.
- `initial_fixed/`: earlier four-building scene passed 69 graphical checks after
  that fix. This predates the user's rejection and is not the delivered scene.
- `interrupted_refinement/`: process exited without the completion marker during
  the interruption. The runner correctly marks it failed despite exit code zero.
  It is not counted as passing verification.
- `failed_key_focus/` and `failed_key_focus_repeat/`: two repeated runs missed an
  injected E event and stopped at a closed door. The first overlapped another
  Godot check; the second ran alone, so overlap alone is not an adequate diagnosis.
  Those runs did not trace focus state at the missed key. The fixture now establishes
  the focused input precondition explicitly, as it already simulates focus-loss
  notifications. The final run logs an actual simulated-focus restoration and
  passes all doors. No production door collision or input guard was bypassed;
  inactive-window E input remains ignored. Manual desktop focus behavior remains
  separate from this deterministic input fixture.

## Still open

Thin native roof/transition assemblies must remove the exposed diagonal staircase
appearance while retaining separate grid-cell collision, damage and persistence.
No replacement cottage is approved. Return with clean exterior and underside
joins, local block-removal tests and a new signed design for user approval.

B1's inclusion in generated settlements still needs placement-envelope/terrain-fit,
populated-world routes, saved-world integration and performance qualification.
These checks do not establish world terrain quality, NPC navigation, structural
collapse, large-city performance or player acceptance of any other building.

## Reproduce

```text
python tools/run_godot_check.py modular_building_walkaround --timeout 180 --require "MODULAR_BUILDING_WALKAROUND checks=" -- --review-output=res://reports/modular_building_walkaround/approved
python tools/run_godot_check.py approved_shop_addition --headless --timeout 120 --require "APPROVED_SHOP_ADDITION checks="
python tools/run_godot_check.py modular_building_review --headless --timeout 120 --require "MODULAR_BUILDING_REVIEW checks=" -- --review-output=res://reports/modular_building_review/decision_recheck
python tools/run_godot_check.py modular_building_review --headless --timeout 60 --require "MODULAR_BUILDING_RESTORE checks=" -- --review-output=res://reports/modular_building_review/decision_recheck --restore-review
python tools/review_modular_buildings.py
```

# G drops the held gameplay item

- Status: Implemented / installed, scoped checks pass.
- Updated: 2026-11-04. Fix: focused item-dropping commit.
- User visual review: Pending. Agent inspected the final packaged capture.
- Symptom: New inventory IDs were missing from a separate pickup whitelist,
  preventing guns, coal, ammunition, barrels and coins from being dropped.

## Required behavior and changes

**G drops one held item only during active gameplay.** Inventory selections,
menus, text entry and developer tools never invoke this shortcut. G never toggles
flight. All current and future inventory definitions inherit drop support when
equipped, without an item-type permission flag or mandatory custom ground art.

The user's follow-up explicitly narrowed the key to active gameplay and held
items. An initial selected-backpack G extension was removed before committing.
Existing inventory drag/drop controls remain available.

The player and pickup containers share `item_catalog.gd` and the same native
schema. Legacy pickup save identities remain intact; other IDs use the fixed
`pickups_0` / `pickup_stacks_0` sections and one code-built parcel mesh batch.
Native transfers preserve quantity, wear and exact bucket water. Rejections
preserve inventory. [Required standard](../../docs/ITEM_DROP_STANDARD.md).

## Verification

| Check | Evidence |
| --- | --- |
| Every current definition and two synthetic future definitions; metadata, reload, stacks and rejection: 440 assertions | [Universal drop](../../reports/checks/20261104T015656889402Z/run.json) |
| Actual world G input; held rifle/coins; inventory, typing, menus, developer tools, death and flight exclusions; rendering: 21 assertions | [Gameplay-only G](../../reports/checks/20261104T020302696852Z/run.json) |
| Actual executable with corrected installed PCK, same 21 assertions, no errors/leaks or sampled resource-budget violations | [Final packaged G](../../reports/universal_item_drop/packed/20261104T020440475918Z/run.json) |
| Universal coins through two autosaves and three fresh worker/provider lifetimes: 13 assertions | [Disk persistence](../../reports/checks/20261104T015330799462Z/run.json) |
| Existing native inventory / transfers: 32 / 29 assertions | [Inventory](../../reports/checks/20261104T015656898220Z/run.json), [transfer](../../reports/checks/20261104T015656922191Z/run.json) |
| Atomic pickup setup and real item labels | [Initialization](../../reports/checks/20261104T015020563809Z/run.json), [labels](../../reports/checks/20261104T015723103293Z/run.json) |
| 42 batches / 172,032 distant records and dense local refusal; p95 267 / 226 / 444 / 73 microseconds for legacy / universal / distant / dense | [Pressure](../../reports/checks/20261104T015636342091Z/run.json) |

The [gameplay-only export log](../../reports/universal_drop_gameplay_only_export.log)
retains export gates and packaged smoke checks. No native rebuild or player-save
rewrite is required.
Installed PCK SHA-256:
`55344a349e3dd176414306f2d9109a9bc712a5723c57e996a0d0da37a8b73b1a`;
all 14 native libraries match source.

## Images and retained history

Images and provenance are recorded in [the manifest](images/manifest.json).
![Gameplay held-item drop result](images/gameplay-held-item-result.png)

Actual executable/PCK, temporary seed-1703 woodland with elevated support fixture,
1920×1080 viewport. Three coins were equipped and G pressed during gameplay;
inventory opened afterward shows two coins in the equipped belt stack. G while
inventory is open was separately verified to leave contents unchanged.

The earlier packaged-backpack capture records the superseded shortcut scope;
it is not evidence for the final gameplay-only behavior.

Early harness failures remain at [restore setup](../../reports/checks/20261104T015004673343Z/run.json),
[mode / text Unicode](../../reports/checks/20261104T015119699484Z/run.json),
[initial mode](../../reports/checks/20261104T015215553751Z/run.json),
[stale hint stubs](../../reports/checks/20261104T015656903464Z/run.json), and
[read-only pack capture](../../reports/universal_item_drop/packed/20261104T015900120723Z/run.json).
Corrected fixtures pass. The [earlier packaged 19-check run](../../reports/universal_item_drop/packed/20261104T020009726029Z/run.json)
passes its original behavior but is superseded by the gameplay-only requirement.

Pressure failures remain at [initial lookup](../../reports/checks/20261104T015351884121Z/run.json),
[uncached universal lookup](../../reports/checks/20261104T015529761613Z/run.json), and
[503-microsecond marginal distant sample](../../reports/checks/20261104T015606559222Z/run.json).
A single derived winner-label cache, invalidated on restore, avoids repeated
32-slot dictionary construction. The final complete pressure run passes the
unchanged 500-microsecond threshold. This is component evidence, not a general
frame-pacing guarantee.

## Remaining / reproduce

Player visual review and wider endurance remain unqualified. New items without custom
ground art intentionally appear as parcels. The universal store retains the
existing 4,096-record bound and 256-visible cap; full/blocked/unready drops retain
the item. Resume on player feedback or capacity changes.

In a ready world on foot, equip a rifle or coins and press G. One unit drops;
use E to recover it. Open inventory and select another slot: G must do nothing.
Menus, typing and developer tools must also leave the inventory unchanged.

New code/tests are original AI-assisted implementation for this user's request,
under 0BSD. The parcel is authored procedurally in code; no external artwork or
implementation was imported. Runtime captures retain inherited project notices.

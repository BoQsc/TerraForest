# G drops the held gameplay item

- Status: Implemented / installed, scoped checks pass.
- Updated: 2026-11-04. Base fix: `436d3022`; physical-drop follow-up below.
- User visual review: Pending. Agent inspected the final packaged capture.
- Symptom: New inventory IDs were missing from a separate pickup whitelist,
  preventing guns, coal, ammunition, barrels and coins from being dropped.

## Required behavior and changes

### Optional physical dropping, enabled by default

**ESC → Player → Physical item drops** now persists an optional default-on global
preference. New drops receive gravity, a slight forward impulse, collision,
bounce and sleep. Off keeps the previous static placement for new drops; existing
physical drops continue. The gameplay-only G rule is unchanged.

The engine owns up to 64 native linear rigid proxies with continuous collision;
there are no per-pickup scene nodes. Pickup IDs, stack metadata and batched art
are retained. Motion and sleep state save in one bounded `pickup_physics` section;
old worlds receive its empty default. Pause/readiness freezes integration while
retaining collision registration, and collection retires its body after the
inventory transfer succeeds. Sleeping proxies may retire for new drops; a full
awake pool rejects new drops without debiting inventory.

Current scope: upright 34 cm box proxies, so artwork does not tumble. Long-range
physics residency is bounded; retired sleeping pickups remain ordinary static
pickups. Exact per-model collision, tumbling and large-population frame pacing
are not qualified. These are explicit limits, not claims of a complete loose-body
world simulation.

Passing follow-up evidence:

| Check | Evidence |
| --- | --- |
| Defaults/preference reload, gravity, bounce, floor CCD, pause/readiness, in-flight restore, metadata, every item plus a future item, pool/corruption rejection: 77 assertions | [Source](../../reports/checks/20261104T022327752202Z/run.json), [actual executable/PCK](../../reports/physical_item_drops/packed/20261104T022459733983Z/physical_item_drops/run.json) |
| Real gameplay G falls; checkbox off restores static placement; inventory/menu/developer exclusions remain: 26 assertions | [Source](../../reports/checks/20261104T021916842233Z/run.json), [actual executable/PCK](../../reports/physical_item_drops/packed/20261104T022459733983Z/drop_key_standard/run.json) |
| Physical state through two disk autosaves / three provider lifetimes: 15 assertions | [Disk](../../reports/checks/20261104T021954921230Z/run.json) |
| Existing universal items: 440 assertions; atomic setup / failed-drop conservation | [Universal](../../reports/checks/20261104T022327750382Z/run.json), [setup](../../reports/checks/20261104T022152040872Z/run.json), [drops](../../reports/checks/20261104T022152068310Z/run.json) |

Both native debug and release builds pass in
[the build log](../../reports/drop_physics_builds_final.log); export gates, smoke
startup and packaged house-light gate pass in [the export log](../../reports/drop_physics_export.log).
Installed PCK `b4bf193145beadba5a12f92412ade66bcb946ae242295299936cd337e8498ea9`,
14 matching native libraries. The first physical fixture
[failed by retaining stale native handles after restore](../../reports/checks/20261104T021728702445Z/run.json);
resolving the persistent identity again fixes the harness. Final runs have no
script errors, leaks or assertion failures. New native code is original
AI-assisted 0BSD; existing engine/binding notices remain unchanged.

![Physical item drop setting](images/physical-drop-setting.png)

Actual executable/PCK, temporary seed-1703 woodland, 1920×1080 viewport. Player
settings show the option on after real G / on-off checks. Agent inspected;
user visual/motion acceptance remains pending. Provenance is in the image manifest.

### Original universal-drop implementation

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

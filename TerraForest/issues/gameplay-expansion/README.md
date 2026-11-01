# Gameplay expansion: encounters, exploration and progression

- Status: In progress; generated house/underground/lookout sleepers and supplies, not a completed expansion.
- Updated: 2026-11-01.
- User review: implementation requested; no new asset/animation approval claimed.
- Scope: [full requirements and acceptance](../../docs/GAMEPLAY_EXPANSION.md).

## Combined package milestone — 2026-11-01

The coordinated expansion package is exported and starts successfully, with all
14 native libraries matching the verified source builds. It includes the coal
mine, combat, trader travel, town signs and both reset primitives. This supersedes
the older primitives' "not installed" notes below, not their limited scope:
gameplay resets are still absent. Exact-executable feature journeys are being
checked serially; no complete expansion or new visual approval is claimed.
[Frozen package identity and pending gates](combined-package-evidence.json).

## Quest ownership foundation — installed and scoped-verified, not playable quests

- Native location identities and TFQ1 state are implemented; trader offers,
  question-mark/E start and actual location reset are not yet wired to gameplay.
- Debug/release initially pass 51 native assertions:
  `reports/quests_native/20261101T155046082842Z` and `20261101T155046846586Z`.
- Normal default generation published four sites, seven actual sleeper anchors
  and seven chest IDs in 620 bytes. First integration report
  `reports/quests_world/20261101T155047564011Z` retains two failures: remote chest
  queries incorrectly ignored paging, and normal save-return timed out. Fallback
  shutdown saved successfully; that is not evidence that normal return works.
- The corrected fixture streams to each site before checking physical chests and
  records save/pager/worker diagnostics. Two additional decoder regressions first
  fail against the previous binary (`reports/quests_native/20261101T160606817860Z`):
  an already-paid active cycle and a binary string silently truncated at a null.
  Both now pass after rebuilding: debug/release 53 checks at
  `reports/quests_native/20261101T160944750121Z` and `20261101T160945858610Z`.
- Corrected normal streaming checks all seven physical stocked chests, followed
  by normal save-return and fresh-process byte-exact restoration: 21 + 10 checks
  in `reports/quests_world/20261101T161019237804Z`.
- Fresh normal generation, immediate first reservation/save, selector reopening,
  all four streamed locations and a fresh-process restore pass 25 + 10 checks in
  `reports/quests_world/20261101T161638198108Z`. Save completion still waited over
  20 s despite only 1.7–1.8 s publication. A reproduced idle-cache priority defect
  now yields to reserved saves; the same owned-world reopen passes 10 checks in
  `20261101T162547622901Z`, with 2.332 s end-to-end save completion. Details:
  [runtime tracker](../runtime-performance/README.md#async-save-completion-versus-optional-cache-work).
- Sampled source peak private commit 3,765,170,176 bytes; dedicated GPU
  1,497,583,616 bytes, within current budgets. No foreground frame-pacing claim.
  Matching combined-package verification now passes: 25 normal-generation/first-save/
  streamed-ownership checks and 10 fresh-process restore checks at
  `reports/quests_world/20261101T165251331454Z`. Package save completion is 1.844,
  2.200 and 1.978 s; the quest capture adds 10–18 microseconds. Package peak private
  commit 3,831,541,760 bytes and dedicated GPU 1,507,872,768 bytes remain within
  current sampled budgets. [Exact installed artifact and evidence](quest-evidence.json).
- No new visual acceptance is claimed. Remaining/reset closure requirements:
  [expansion contract](../../docs/GAMEPLAY_EXPANSION.md#native-location-ownership-and-quest-state).

## Bounded terrain reset primitive — source verified, not gameplay

- Native TFP1 density/material patches pass rebuilt debug/release checks; no
  gameplay reset, new UI or existing-world modification is enabled. Distribution
  remains unchanged; the shared native artifact commit awaits the vehicle source.
- Standalone debug/release checks pass at
  `reports/terrain_field_patch/20261101T171822674934Z/run.json`: 32 checks per
  variant, including 96 allocation-fault attempts and 32 forced failures each.
  Outside authored samples, stale revisions, malformed input and residency-failure
  rollback are covered. A maximum patch is 3,145,776 bytes; these cold-kernel timings
  are not frame-pacing evidence and ran during other coordinated build work.
- Final standalone checks add capture-allocation failure, passing 33 per variant
  at `reports/terrain_field_patch/20261101T173629541232Z`. Rebuilt bindings pass
  another 33 per variant at `reports/terrain_field_patch_binding/20261101T173628376880Z`:
  deferred page reads, dirty versions, geometry keys, epoch rejection, durable
  checkpoint publication and fresh-owner restore preserve neighboring edits.
- The final 35-check adapter run at
  `reports/terrain_field_patch_binding/20261101T174526651866Z` also warms the native
  mesh cache, restores the field, and verifies that the cached mesh matches fresh
  meshing instead of retaining the pre-reset surface. This is geometry parity,
  not rendered multi-owner quest-reset acceptance.
- Retained failed fixtures: the first adapter attempt used brush material 7,
  which ordinary editing correctly rejects; it now uses supported material 2.
  The unnecessary isolated headless editor import also exited with 0xc0000005;
  a previous-installed-DLL control reproduced the same exit. Direct headless
  script checks pass without editor import. The older edit atomicity probe passes
  its 704 allocation-fault attempts but fails its prechange golden-file hashes;
  its core/probe inputs are unchanged by this patch. That mismatch is not waived
  or reported as passed. [Exact reports and native identities](field-patch-evidence.json).
- Complete multi-owner reset remains open in the
  [expansion contract](../../docs/GAMEPLAY_EXPANSION.md#native-location-ownership-and-quest-state).

## Bounded building-cell reset — source verified, not gameplay

- TBP1 includes empty cells as well as shape words, so restoration removes new
  construction without overwriting outside cells sharing the same chunk.
- Both rebuilt native variants pass 28 checks. The full region suite passes 73,
  prefab transactions 36, structures/history 294 and model-admission history 31;
  worker replacement, 200 edits and 40 shutdown cycles also pass.
- A reentrant edit-admission callback could previously replace a staged chunk
  after a newer edit. Revision/epoch checks now reject that stale publication.
- Maximum serialized patch: 524,356 bytes. Maximum-volume sparse fixture capture
  is 4.45–6.11 ms and restoration 4.60–5.72 ms, not dense gameplay/frame-pacing
  evidence. Chunk/neighbor mesh restoration is checked headlessly.
- The first full-suite run failed at parsing an untyped test variable; corrected
  and rerun, with failed evidence retained. Compiler-only syntax mode also failed;
  ordinary compilation and both full native builds succeeded.
- No gameplay reset, asset redesign or existing-world mutation is enabled. Native
  artifacts include concurrent vehicle streaming changes; their source commits
  precede the coordinated artifact commit/export. Remaining multi-owner safety,
  baseline retention, rollback and normal-world acceptance stay open.
- [Exact reports and native identities](block-patch-evidence.json).

## Images

### Inventory navigation — source/package verified and installed

![Installed package after fresh-process restoration of the equipped outfit](images/character-installed.png)

This installed-build capture verifies the combined navigation and separately
authored woven pack. It is a different owned fixture/viewpoint than the source
captures below, not a lighting or terrain before/after comparison.

![Current-player model beside equipment and the separate backpack](images/character-navigation.png)

![The same generated-world map embedded beneath the shared top navigation](images/map-navigation.png)

These source captures show the owned survival fixture, not a changed player save.
The model uses a sampled authored idle pose and one-shot viewport, not continuous
rendering. All six destinations share the top bar and one close button; Quests
honestly reports that contracts are not implemented yet. Equipment still uses
real native revision-checked transactions. Clothing appearance is being authored
separately and is not claimed by these captures. [Capture provenance](navigation-evidence.json).

- Source HUD: `reports/inventory_navigation/20261101T150927066209Z`, 24 checks.
- Source generated world, actual local viewport ESC/M input:
  `reports/inventory_navigation/20261101T151431585586Z`, 21 checks, zero pointer captures.
  First ESC closes inventory/map; second opens pause. Standalone M retains movement.
  Saved journal, actual map imagery and unchanged inventory/equipment verified.
- Source world peak private commit 3,729,375,232 bytes; dedicated GPU 1,489,530,880
  bytes. Individual warm-model portrait creation 5,732 microseconds in
  `20261101T150930979649Z`; isolated cold load about 1.2 seconds. Off-screen checks
  are not a visible 60-FPS frame-pacing qualification.
- Regressions: survival HUD `reports/player_survival/20261101T151506065883Z`;
  progression gameplay `reports/checks/20261101T151506916110Z`; backpack
  `reports/checks/20261101T145930327914Z`.
- Retained failures: `20261101T150205955851Z` exposed an incorrect assumption that
  the viewport mode property automatically switches from ONCE to DISABLED; explicit
  post-draw disabling now matches the contract. `20261101T150412525914Z` exposed
  wrong ESC priority and blank/oversized embedded map; corrected input ownership,
  deferred layout and resize redraw. Intermediate clipped destination list was
  replaced with the compact selector, not hidden or omitted.
- Matching package: `reports/inventory_navigation/20261101T153034644333Z` (24 HUD)
  and `20261101T153039281988Z` (21 generated-world input/layout checks).
  Packaged clothing checks pass 49 assertions at
  `reports/woven_clothes/20261101T153115340716Z`; fresh-process restoration of the
  existing owned clothing world passes 8 at `20261101T153120603692Z`.
  New package-world paid crafting/equip/save/reopen passes another 15 + 8 checks
  at `reports/woven_clothes/20261101T153321253890Z`.
  The installed PCK is 447,961,500 bytes, distribution 477,885,907 bytes, SHA256
  `dec302a978bf81dd2bb27b53351f00740d7587aae4fb17b44bc46df349eee835`.
  Credits, icon freshness, building-standard gates, 14 native DLL hashes and startup
  pass. Package-world private commit peaks at 3,698,749,440 bytes and dedicated GPU
  at 1,489,592,320 bytes; this remains off-screen memory evidence, not frame pacing.
  Final package map and equipped-portrait images were inspected.
- Remaining: user presentation review, real
  trader contracts/POI reset, broader input and performance, all other open rows.
  No earlier terrain, lookout-travel or frame-pacing failure is closed by UI tests.

### Food, reading and survival — source/package verified and installed

![Installed package: a looted letter retained in Journal after consumption and reload](images/journal-restored.png)

![Installed package: finite food and readable offers, preserving selected offer visibility](images/food-trade-restored.png)

These are actual generated-world UI captures, inspected for readable text, baked
item icons and uncluttered side tabs. The merchant behind the transparent Journal
is a world actor, not the requested character preview. [Capture provenance](survival-evidence.json).

Three original readable items and three foods have baked models/icons and enter
ordinary exploration/rare locked-chest loot and finite trade. Native atomic use
backs held-use routing, double-click and Use context menu; read texts persist in
Journal. Food, Well fed damage and Focused XP modifiers use bounded active-time
counters and compact binary saves. Menus/loading/unfocused time do not drain them.
Existing worlds gain newly introduced merchant supplies once; original stock and
coins are not replenished, full inventory additions remain queued, and sold-out
versioned stock stays sold out. New chests are not inserted into existing saves.

- Native debug/release: `reports/player_survival/20261101T143513788647Z` and
  `20261101T143514504279Z`, 31 checks each, including malformed/atomic restore,
  stale and duplicate use, expiry, fullness, low-food penalties, stable catalog
  expansion, legacy merchant migration and full-stock pending delivery.
- Real HUD: `reports/player_survival/20261101T143608551538Z`; double-click, Use,
  stale context rejection, held-slot shared transaction, Journal, timer, icons/drops
  and separate backpack/toolbelt pass. Native clock is accelerated in eating tests.
  Final `20261101T144539436773Z` passes 20 checks, adding actual finite food purchase
  and selected-offer scrolling. The expanded merchant list previously jumped to
  its top after refreshing a bottom-row purchase; it now retains visible selection.
- Default browser generation: `reports/player_survival_world/20261101T142952160860Z`
  created the owned `Survival_1703_56805d64` world. Initial fixture selected nearby
  rare chests rather than authored underground supply chests and failed its required
  beans/bread assertion. Corrected selection continued that same world, not a new
  generation or test grant: `20261101T143158747842Z`, 36 interaction + 12 reload checks.
  Actual generated chest contact/open/withdrawal, selling gathered stock/buying food,
  dropping/picking, reading, eating, real timer pause/advance and exact save pass.
- Current native merchant migration and corrected uncluttered Journal restore:
  `reports/player_survival_world/20261101T143609495832Z`, 12 fresh-process checks.
- Trader and lock-gameplay regressions: `reports/checks/20261101T143656095898Z`
  and `20261101T143657183486Z`. Earlier survival UI parse fixture failure retained
  at `reports/player_survival/20261101T142104330284Z`; fixed lambda scope in test.
- Source interaction peak: 3,638,898,688 bytes private commit and 1,489,264,640
  bytes dedicated GPU. Short offscreen scripted tests are not 60-FPS pacing,
  traversal, captured-input or eating/reading animation qualification.
- Package default Generate & play: `reports/player_survival_world/20261101T144039859117Z`,
  new owned `Survival_1703_d2f72c5e`, 37 interaction and 12 reload assertions. Different
  authored locations supply different readable items; ordinary finite trade and
  preserved stock, food/buffs, reading/XP, looted contents and native drops pass.
  Final UI-only correction export: `20261101T144707459837Z`, another 14 restore/UI
  assertions and exact native parity. All 14 native libraries match the installed
  PCK. Original played worlds are untouched; legacy migration is additionally
  exercised on native old-format fixtures and the source-created owned save.
- Packaged creation/travel peak: 3,759,775,744 bytes private commit and 1,472,806,912
  bytes GPU; final reopen: 3,626,541,056 and 1,472,745,472 bytes respectively. The
  captures show below-cap FPS during these scripted/offscreen sessions; this is
  memory qualification only, not a claim that existing stutters are resolved.
  PCK 447,481,348 bytes; distribution 477,405,755 bytes. Credits, building standard
  gates, icon freshness, native parity and packaged startup pass. Progression and
  backpack regressions: `reports/checks/20261101T143850314651Z` and `20261101T143851423007Z`.
- Remaining: user art/presentation acceptance, broader input and
  balance review, renewable food sources, full navigation/3D character, quests and
  all remaining expansion requirements. Original asset provenance is adjacent to
  `addons/player_runtime/art/consumables/`; no new third-party assets.

### Player progression — source/package verified and installed

![Installed package: earned level and Mining skill restored in the owned seed-1703 world](images/skills-restored.png)

The image shows actual earned 253 XP and a spent Mining point after fresh-process
reload, not a developer grant. Existing passive HUD overlaps the old side-tab
area; the requested full navigation redesign remains open. Camera/viewpoint differs
from the mining view, so this is UI/save evidence, not a terrain before/after.
[Capture and package provenance](progression-evidence.json).

Native XP, levels, points and Mining/Woodcraft/Melee ranks are connected to
published mining, natural harvesting, living-zombie damage and paid crafting.
Skills are accessible beside Crafting/Character; the full requested top navigation
is not complete. The existing five-row resource feed aggregates XP without idle
polling. Initial saved state is 48 bytes, bounded to 280 bytes for 32 skills.

- Native debug/release: `reports/player_progression/20261101T135312891896Z` and
  `20261101T135313495577Z`, 26 checks each: cap/thresholds, stale revision, malformed
  atomic restore, overspending, skill bounds and adding skills to older saves.
- Real HUD/native stores and crafting/mining/combat adapters:
  `reports/checks/20261101T135049409040Z`, 19 assertions. Synthetic edit publication
  and enemy health in this fixture are not actual world excavation/combat.
- Ordinary generated-world source: `reports/player_progression/20261101T134707497088Z`,
  50 earn/spend assertions and 8 fresh-process assertions. Native visible-ground
  rays feed the real pickaxe contact adapter; actual generated trees are harvested
  through their native-backed owner. No test XP grants; 253 cumulative XP earns
  level 2 and a Mining rank. Exact XP/ranks, gathered items, crafting costs and tool
  wear reload. Scripted target/position selection is not an input-animation or
  walking qualification. Only the owned `Exploration_1703_8f8d4c8f` world changes.
- Source sampled peaks: 3,708,997,632 bytes private commit and 1,490,513,920 bytes
  dedicated GPU memory; short offscreen checks, not frame-pacing/endurance proof.
- Legacy crafting/backpack tests pass (`reports/checks/20261101T134742845857Z`,
  `20261101T134743835009Z`); debug/release container suites remain green at
  `reports/container_locks/20261101T135050704956Z` and `20261101T135053334591Z`.
- Installed matching PCK: `reports/player_progression/20261101T135527577997Z`,
  8 fresh-process assertions for XP/ranks, inventory/wear, active damage modifier
  and zero pointer capture. Native hash parity, building gates and pack startup
  pass. Package size 447,314,276 bytes; distribution 477,164,955 bytes.
  Packaged sampled private commit 3,666,939,904 bytes and GPU 1,490,513,920 bytes,
  not a general frame-pacing or minimum-hardware claim.
- Retained fixture failures: `reports/checks/20261101T133932362644Z` used a nonconstant
  packed-array constant; `reports/player_progression/20261101T134315093670Z` wrongly
  required GPU telemetry from a headless native check. Corrected test configuration,
  not relaxed graphical memory limits. `20261101T134315647793Z` and
  `20261101T134434970119Z` did not earn 250 XP from shallow soil cuts; the passing
  continuation combines actual felling and mining without changing XP thresholds.
  The first attempt verifies absent-component migration from the old fixture save.
- Remaining: readable items/consumption, hunger/buffs, full
  inventory navigation, populated ordinary combat and progression balance. Natural
  resource/contact guards are not a complete anti-grinding system; terrain cycling
  still trains by doing at the cost of tool durability. Existing route/performance
  failures and every other full-contract row remain open.

### Container locks — source and package verified, 2026-11-01

![Actual generated house chest retains 150 of 180 lock durability after a hatchet hit](images/container-lock-damaged.png)
![Generated chest opened with a crafted lockpick; supplies and reusable picks remain](images/container-lock-picked.png)

New-world generation selects one in five chests deterministically; selected empty
house chests receive supplies, while existing exploration supplies are retained.
Locks have 180 health (twice the normal chest). E uses a craftable/tradable pick,
with a 10% chance of breaking one; success retains the pick. Tool damage opens the
lock without deleting the container or its contents. Existing saves are not
retroactively locked or replenished. Lock state, partial damage and random state
are native, bounded and binary; no idle polling or replacement model is added.

- Native debug/release: `reports/container_locks/20261101T130327483421Z` and
  `20261101T130330320349Z`: 56 lock assertions each plus legacy container/drag/
  capacity/transfer suites. 1,000 deterministic attempts give 105 broken picks;
  4,096 lock-only records use 98,328 bytes. This is not gameplay frame timing.
- Real HUD/storage/attack/crafting adapter, fake collection/picking:
  `reports/checks/20261101T130906940034Z`, 24 assertions. Icon visually inspected.
- New ordinary generation succeeded in
  `reports/exploration_world/20261101T130043255160Z`, but the broad traversal test
  failed at the previously observed second-lookout return walk before checking
  locked chests. Retain this recurrence, not a passing world qualification.
- Actual generated-world interaction: `reports/container_lock_world/20261101T131517785107Z`,
  30 assertions plus 11 fresh-process assertions. Native scene rays select real
  generated chests; hatchet contact adapter breaks the first lock, ordinary chest
  UI collects iron, backpack crafting converts iron → metal → picks, E unlocks
  another chest, and a third lock retains partial damage across compound saves.
  Images inspected; [capture provenance](container-lock-evidence.json). Peak
  sampled private commit 3,681,587,200 bytes, dedicated GPU 1,490,513,920 bytes.
  These offscreen interaction captures do not establish 60-FPS frame pacing,
  street-to-interior traversal or authored animation/input timing.
- Retained fixture failures: `20261101T131146397565Z` refused launch at the free-space
  safety reserve; `20261101T131255627535Z` assumed starter metal and omitted the
  existing offscreen scene-transition hook. Corrected fixture collects real loot
  and records zero pointer captures in both passing phases. No limit was disabled.
- Combined door/lock package restores the same owned world with 11 passing
  assertions: `reports/container_lock_world/20261101T132734256039Z`. Exact remaining
  lock damage, contents, picks and worn tool match; no desktop pointer capture.
- The combined source and PCK/native libraries are installed in the main checkout
  with matching hashes; door and lock integration evidence is linked from
  [the door verification receipt](../door-animation/verification.json).
- Remaining: direct player animation-input playtest. The dedicated lock-world check reuses only that owned
  `Exploration_*` save; it does not replace the failed lookout route requirement. Locked doors,
  barricades and POI quest reset ownership remain separate unfinished work.

### Generated W1 lookouts — 2026-11-01

![Installed world: lookout on a fitted local foundation and connected footpath](images/watchtower-world-approach.png)
![Installed world: upper-deck supplies and resident encountered during waking](images/watchtower-world-deck.png)

The ordinary unchanged default Generate & play recipe now includes up to two
separated lookouts. Shared native fitting handles diagonal/curved regional roads,
retains the existing 2 m fill / 3 m cut limits and protects lakes, buildings and
underground sites. At most 192 candidates are tested once during planning. Two
sites fitted in 12.704 ms in the isolated seed-1703 planning measurement; this is
not whole-world generation time. No existing save or approved house is replaced.

Construction remains 385 individually destructible cells, batched by the existing
native world. The deck chest has actual thin-floor support and clear-bound checks,
stocked supplies and a stable sleeper; native binary storage preserves withdrawals
and cleared residents. New roof geometry appears in generation preview, and actual
entrances/approaches are in the native regional plan. There is no frame-loop survey.

- Source ordinary world: `reports/exploration_world/20261101T120954902588Z`, 76
  generation/travel/loot/wake assertions and fresh-process restoration. Both towers
  are reached from their real roads, climbed, looted and descended; the cave/mine
  interactions remain covered in the same populated world.
- Fifteen siting/cache/malformed-road assertions:
  `reports/checks/20261101T120953037834Z`. Seven-seed legacy lot planning passes at
  `reports/checks/20261101T121405129828Z`. Required source/release building gates:
  `reports/building_standards/20261101T121730382946Z`.
- Source travel: 2,157 samples, p95 18.340 ms, worst 38.854 ms; peak private commit
  3,802,275,840 bytes and dedicated GPU 1,490,579,456 bytes. Offscreen 1080p, capped
  60 FPS/VSync, Quiet Mode unchanged. This does not qualify smooth foreground 60 FPS.
- Retained failures: first road-return timeout (`20261101T120104107970Z`, not
  reproduced in subsequent source traversal); a test-owned shared route was
  reversed in-place (`20261101T120630769200Z`, fixed by duplicating before mutation).
  A headless material-startup crash remains recorded in
  `reports/watchtower/20261101T115429631373Z`; rendered review passes separately.
- The legacy raw earthworks test reports two pavement-support failures, reproduced
  identically in the old installed pack at
  `reports/watchtower_baseline/20261101T121702667145Z`. Do not present that check as
  green; the current production source/release contact gate passes.

Installed-package generation and fresh restoration pass 76 + 15 assertions at
`reports/exploration_world/20261101T122106715365Z`. Package travel p95 is 17.014 ms,
worst 38.401 ms across 2,157 samples; peak private commit 3,862,499,328 bytes and
dedicated GPU 1,490,579,456 bytes. These remain offscreen measurements, not a claim
of seamless foreground frame pacing. Exact shipped W1 resource, four rotations,
missing-deck/obstructed-prop rejection and local destruction pass 55 assertions in
source (`reports/watchtower/20261101T122522042640Z`) and package
(`reports/watchtower/20261101T122557845008Z`). Distribution budget: 476,824,047 bytes.

The coordinated browser update is also included; packaged responsiveness and
credits UI checks pass. A first credits harness incorrectly wrote into read-only
`res://` and used headless screenshot capture; its failed evidence is retained,
then the unchanged assertions pass with an external output directory and renderer.
Exact package, resource and image provenance: [integration evidence](watchtower-world-evidence.json).
Return for broader seeds, full NPC routes, final visual review and foreground
performance. Quest/reset/lock ownership and the full expansion remain unfinished.

### Watchtower W1 review — 2026-11-01

![W1 lookout: separate grid pieces, two stair flights and sheltered deck](images/watchtower-w1-front.png)
![W1 deck, stair opening and chest attachment](images/watchtower-w1-deck.png)

Original `addons/exploration/watchtower.gd` authors the CC0 baked
`watchtower_w1.tres`: 385 independent native cells, smooth shallow metal roof,
weathered timber supports/guards, switchback stairs and one existing chest model.
No houses were replaced. At this historical isolated-review checkpoint the chest
was only an attachment; current generation/loot evidence is recorded above.
This isolated review alone does not qualify natural terrain fit or generation.

Checks use actual `NativePlayerMovement` and native block/model collision: climb
both flights, cross the deck and descend in all four grid rotations. They also
check continuous support columns, exact baked-resource correspondence, independent
roof-cell removal and binary restoration. No whole-tower runtime mesh/Node per
piece, per-frame authoring or new native library is required.

- Source render: `reports/watchtower/20261101T112343447658Z`, 35 checks, including
  baking the corrected resource. Final exact-resource parity is checked separately.
- Final source headless: `reports/watchtower/20261101T112757477833Z`, 35 checks,
  including exact baked-resource parity. Godot import succeeds and generated both
  new script UIDs: `reports/watchtower_import/20261101T112627831928Z`.
- Release-native render: `reports/watchtower/20261101T112536612254Z`, 35 checks.
  The external review recipe/driver uses installed pack materials, models and
  release DLLs; this does **not** mean the watchtower is in the installed catalog.
  Sampled private commit 1,342,844,928 bytes / dedicated GPU 662,040,576 bytes for
  this isolated scene, not populated-world headroom evidence.
- Initial failures retained: `20261101T111351568799Z` (low beam obstructed stairs),
  `20261101T111449111215Z` (guard mounted across upper landing),
  `20261101T112141544296Z` / `20261101T112305547662Z` (discontinuous support column).
  Fixes change authored cells, not controller tolerances or grid rules.

![Rejected early lookout with disconnected support joints](images/watchtower-rejected-support-gaps.png)

The integration entry above supersedes this checkpoint's pending fitting,
publication, supplies and persistence work. Existing saves remain untouched;
broader quality/performance and final user visual approval are still not claimed.

### Portal correction — 2026-11-01

![Original cave location with the thin roof remnant removed](images/cave-portal-original-site-after.png)
![Revised cave in a normal generated world](images/cave-portal-world.png)
![Revised mine entrance in a normal generated world](images/mine-portal-world.png)

The isolated patch above the old entrance was not missing mesh. Density sampling
found only 0.1–0.2 m of rock at the affected roof column, thinner than the metre
density lattice. The authored open-air recess removes that layer and leaves a
readable rock face before the covered passage. No shader, global lighting, grid
or load-time terrain patch changed. The first image uses the **original** bad
site `(1425,183,1348)` and camera; comparison source before:
`reports/exploration_review/20261101T102303021939Z/split_rock_cave_0.png`, after:
`reports/exploration_review/20261101T105118945887Z/split_rock_cave_0.png`.
This prototype was then moved into the validated ordinary catalog/native planner,
not left as a test-only correction. Stronger footprint support fitting selects
`(1629,158,569)`, rotation 1, for the new seed-1703 cave. The mine stays at its
original site. Existing saved worlds retain their original excavations.

- Native debug/release: `reports/exploration_native/20261101T105746209194Z` and
  `20261101T105748357629Z`; 25 + 74 + 23 checks each. A regression reproduces the
  old solid wafer, checks its actual removal, retains floor/covered roof support,
  and rejects malformed/nonfinite/oversized mod entrance cuts without mutation.
- Actual final-catalog collision/waking review: `reports/exploration_review/20261101T105630297579Z`,
  26 checks. All four layout rotations and five native fit seeds still pass.
- Source ordinary Generate & play + fresh restore:
  `reports/exploration_world/20261101T105825197235Z`, 28 + 11 checks. Physical
  entrance walks, chest withdrawal, sleeper wake, saved clearing and zero cursor
  captures pass. Sampled peak private commit 3.44 GiB / dedicated GPU 1.39 GiB.
  Offscreen walking p95 20.070 ms, worst 33.080 ms, 466 samples; not smooth-60 or
  foreground headroom acceptance. Quiet Mode and 60 FPS/VSync remain unchanged.
- Required source/release building gate: `reports/building_standards/20261101T110254579860Z`.
- Packaged ordinary generation + fresh restore:
  `reports/exploration_world/20261101T110609763419Z`, 28 + 11 checks; entrance
  screenshots inspected. Sampled private commit 3.56 GiB / GPU 1.39 GiB; walking
  p95 19.857 ms, worst 30.663 ms across 466 samples. Full harness 103.68 s create /
  29.14 s restore, not generation-only timings. Distribution 476,782,715 bytes.
  Installed pack hash and capture provenance are in `portal-evidence.json`.

This closes the reproduced isolated portal wafer, not all terrain shading/art.
The cave still needs richer natural detail; the mine needs more authored dressing,
and external paths/NPC routes plus broader performance remain unqualified.

### Generated underground locations — 2026-11-01

![Survey mine in an ordinary generated world](images/survey-mine-world-entrance.png)
![Mine supply chest reached through actual player movement](images/survey-mine-world-chamber.png)
![Cave entrance with unresolved faceted/dark rim patches](images/cave-world-entrance.png)
![Cave supply chest](images/cave-world-chamber.png)

Seed 1703, normal default browser recipe, source run
`reports/exploration_world/20261101T102919511519Z`. Captures are unedited; existing
materials/models retain their original provenance. Timbers are 33 destructible
grid blocks, not one mine mesh. The mine branches and loops; the smaller cave has
two connected chambers. Actual collision-driven approach/room walks, chest UI,
withdrawal, hearing/wake and separate-process restoration pass. Teleporting to the
approach does not qualify travel from town. Dark angular cave-rim patches and
sparse dressing remain visible defects, **not final art approval**. The separate
[unshaded diagnostic](images/cave-entrance-geometry.png) shows surface geometry at
that patch; the later portal correction above supplies the density diagnosis.

- Native debug/release: `reports/exploration_native/20261101T103315815064Z` and
  `20261101T103318338898Z`; 25 arched-density, 66 layout/route/fitting and 23
  model-only atomic-placement checks each. Includes flat-floor exact-cube safety,
  five deterministic seeds, all rotations, reject/no-mutation and binary reload.
- Standalone visual/collision: `reports/exploration_review/20261101T102303021939Z`,
  26 checks, shared production support/clearance gate and native sleeper wake.
- Ordinary world create/restore: `reports/exploration_world/20261101T102919511519Z`.
  Two sites, five stocked chests, five keyed sleepers; actual looted contents and
  killed resident survive a fresh process. Old saves are not repopulated.
- Matching installed pack create/restore passes:
  `reports/exploration_world/20261101T103815729207Z`, SHA-256
  `852158e09857496452c1723074dbdab39166c1fc668c9c2a6eb0ced23db6b305`.
  Pack size 447,074,612 bytes; source/package entrance images inspected. Its 466
  offscreen walking frames have p95 22.018 ms and worst 78.687 ms: **remaining
  performance work**, not a smooth-60 claim. Sampled peak private commit 3.566 GiB,
  dedicated GPU 1.401 GiB. Controlled foreground comparison remains necessary.
- Source walking window: 466 frames, p95 18.325 ms, worst 32.883 ms. These are
  offscreen physical-controller walks, **not** foreground pacing or smooth-60
  approval. Sampled peak private commit 3.442 GiB and dedicated GPU 1.387 GiB;
  0.5-second process-specific counters do not capture every instantaneous peak.
  FPS shown during screenshot readback is not a benchmark. 60 FPS/VSync and
  Quiet Mode are unchanged.
- Existing container, real-prefab, frontage and terrain contract tests pass;
  required source/release building gate: `reports/building_standards/20261101T103446324792Z`.
- First ordinary-world run `20261101T102618255608Z` is retained as **failed**:
  the test's initial offscreen flag was reset during scene transition, permitting
  mouse capture. The harness now sets it before the world enters the tree and
  asserts zero captures both at readiness and exit. Passing rerun retains normal
  collision but opens the movement gate without OS capture; it is not an input
  or foreground-performance qualification.
- Other retained rejects: `exploration_review/20261101T095955750134Z` (wrong
  approach material/camera inside wall); `exploration_native/20261101T100715626549Z`
  (stale release binary launched before build ended); `exploration_native/20261101T102238121129Z`
  (test Variant-inference parse error). Earlier native/visual failures remain in
  `reports`; no failed cache or review image is silently removed.

Next: rim/art refinement, watchtower and external paths, then persistent location
ownership/reset and locked access. Loot seeding is generation-only, not quest
reset. Dense encounter balance, general NPC routes, broader seeds/recipes and
foreground/doubled-content performance remain open.

Implementation: `addons/exploration/`, native `exploration_sites.hpp`, native
arched terrain profile, `NativePrefabPlacement.ground_model_samples`, the shared
foundation state machine, exact committed-model IDs and native container grants.
`custom_world_plan.gd`/`generate_world_task.gd` are the ordinary-generation hook;
there is no load-time regeneration or new frame-loop excavation.

![Generated forearm-loss resident](images/seed1703-forearm-variant.png)

Seed 1703, ordinary population resident 1622, installed pack `62f9267e618e`.
The missing right forearm/hand has a closed stump; remaining anatomy is unchanged.
Two source angles and this packaged front view were inspected. This is an anatomy
image, not new character art or animation approval. Screenshot readback/off-screen
capture is outside the timed intent samples; the HUD FPS is not performance evidence.
Jogging, new POIs/models and populated-world balance remain unreviewed.

### Sleeper animation checkpoint

![Seated wake, side](images/sleeper-seated-wake.png)
![Lying wake, side](images/sleeper-lying-wake.png)
![Missing left shin, crawling exit](images/sleeper-crawl-missing-shin.png)

Actual original R4 runtime skin, flat authoring stage, 2026-11-01. Left to right:
start, 30%, 65%, completion. Assistant inspected front/side, forearm-loss and
shin-loss views. These are authored animation reviews, not live sleeper behavior,
physical clearance, terrain/POI suitability or user approval.
[Normal-speed front/side video](images/sleeper-wake-normal-speed.mp4) contains all
four wake clips, 480 frames at 30 FPS; readback/encoding is not gameplay timing.

Rejected trials are retained: [initial floating hips](images/rejected-sleeper-v1-floating.png)
and [linear seated-to-crawl leg penetration](images/rejected-seated-crawl-v2-floor.png).
The latter is replaced by authored leg arcs, not hidden geometry or a runtime lift.

## Changes and verification

- Native configurable temperaments, sustained-notice and finite-pursuit rules.
- Native sleeping/waking handshake: sound or hit begins wake; no combat/movement
  until the host acknowledges elapsed animation and safe physical transition.
- Stable native initial limb-loss recipes, using existing binary health storage.
- Restoring missing limbs no longer allocates throwaway detached ragdolls.
- Debug and release: 58 new native checks, 31 awareness, 33 population and 50
  anatomy checks pass; release fresh-process population restoration passes four.
  Existing actual-body crowd/contact (17) and navigation (15) checks also pass.
- Ordinary seed-1703 source and installed-pack scenes each pass 47 admission,
  anatomical presentation and scene-reload checks. All three temperaments appear;
  two of six admitted residents have generated missing forearm/hand chains.
- Short installed six-resident sample: intent p95 159 microseconds; process private
  commit 2,738,499,584 bytes, dedicated GPU 1,221,558,272 bytes. This does not prove
  crowded combat, frame pacing, dense POI streaming, driving or endurance headroom.
- Export/mandatory building gates pass; installed content is 476,294,851 bytes.
  60 FPS, VSync and Legion Quiet Mode are unchanged. All 33 pre-existing local
  import/project/icon files are hash-preserved; no user save was opened for writing.
- Exact evidence: [first milestone record](encounter-evidence.json).

- Sleeper asset checkpoint: two breathing poses, two standing wakes, two crawling
  exits; 59-bone rest match, exact original-idle endpoints, seven neutral morph resets.
  All six clips are original key-pose/IK work with retained rig provenance.
- 57 pose assertions inspect every 60-Hz frame, finite transforms, fixed root,
  floor clearance, endpoints and native skin/envelope containment. Lowest skin is
  about -0.51 mm at the inherited crawling-hand endpoint, within the 5 mm test
  tolerance. Tests do not qualify self-contact, arbitrary slopes or live collision.
- Shared runtime library: 316,364 bytes, reduced from an approximately 1.5 MB
  unoptimized intermediate. Native bounds are baked offline into 12-Hz groups;
  no runtime per-frame vertex sampling has been added.
- Preserved failed checks include an initial converter ready-order error and two
  launcher expectations (GPU telemetry in headless mode; a guessed assertion count),
  plus an initially read-only packed report destination. All are corrected without
  changing pose acceptance thresholds; packed runs use explicit writable reports.

Asset checkpoint evidence: [source/pack checks, hashes and retained failures](sleeper-evidence.json).
That animation-only checkpoint's pack passes 57 pose assertions and 47 ordinary
resident world assertions; it does not test live sleepers. Its content size is
476,617,743 bytes. Quiet Mode and the 60-FPS cap are unchanged.

### Live sleeper checkpoint

![Living side-lying sleeper in the flat collision fixture](images/live-sleeper-lying.png)
![Fresh-process reload preserves the crouched wake below a low ceiling](images/live-wake-reloaded-blocked.png)
![Mid-wake leg loss exits into crawling](images/live-wake-missing-leg.png)

Source and packaged runtime runs each pass 47 live checks plus five fresh-process
checks. The matching pack also passes 58 pose checks, 25 binary-state checks plus
three fresh-process checks, and 47 ordinary-resident world regressions. Details,
hashes, limits and retained failures: [runtime evidence](sleeper-runtime-evidence.json).
These images are a flat collision fixture, not approved cave/house placement.

### Generated house checkpoint

![Lying sleeper in an ordinarily generated cottage](images/house-generated-sleep.png)
![Awakened resident after fresh-process world reload](images/house-awake-reloaded.png)

Installed pack `d6aac5e88aa9`, default browser recipe, seed 1703,
`SleeperHomes_1703_2a080445`, resident 2501. Exact approved A2 house; no geometry
replacement. Assistant inspected both captures; no user visual approval claimed.
Source and pack pass generation/wake/injury/clearing restoration. The packed
four-process sequence passes 41 assertions including hidden nonloading admission;
both native DLL variants pass key/capacity/legacy tests. Existing live sleeper
47+5 and surface-resident 47 checks still pass. Exact reports, hashes and retained
failures: [house integration evidence](house-sleeper-evidence.json).

Whole packed phases peak at 3.45 GiB process private commit and 1.37 GiB dedicated
GPU memory. These are short functional tests, not endurance/headroom proof.
The offscreen captures show 47–50 FPS shortly after loading; they do not establish
locked 60-FPS gameplay. The 60-FPS cap, VSync and Quiet Mode remain unchanged.

## Remaining / resume here

Live wake coordination now uses the real encounter host and one collidable body,
native clearance, bounded retries, physical completion before combat, damage/noise,
leg-loss reversal and the existing ragdoll death path. Binary version-three resident
records preserve sleep pose, animation cursor, elapsed wake time and heard source;
legacy saves retain their layout. Flat-host reload exposed a float32 envelope-bin
boundary bug; the runtime lookup now uses the same boundary across serialization.

House sleepers now use stable native keys and authored anchors in unchanged A2/C1
resources. Default ordinary generation creates them before player arrival; loading
an older world does not add enemies. V4 binary records retain cleared-house
tombstones and exact awake/sleeping state. A short floor probe fixes interior
restoration selecting the roof. Both poses clear the actual furnished prefabs in
all four rotations (80 collision/admission assertions); default source cottage
generation, waking, damage, death and fresh-load clearing pass. Nonloading hidden
admission is checked separately, without changing the six-active-body budget.

Next: crafted off-road watchtower/mine/cave locations, their terrain-fit and route
review, then quest ownership/reset, supplies and locks. Populated C1 arrival,
natural street-to-room walking, arbitrary slopes and moving obstacles still need
evidence; prefab collision coverage is not world-quality acceptance. Continue
every remaining row in the linked full contract. Existing
60-FPS frame-pacing defects remain separately tracked, not reset by this work.

## Reproduce / history

Use `tests/zombie_expansion.gd` for native profile/sleep/variety contracts, alongside
existing awareness, population, anatomy, encounter and navigation checks. Use
temporary worlds or explicit test clones, never mutate user saves for evidence.

Repeat: `python tools/check_zombie_expansion.py native --release` and
`python tools/check_zombie_expansion.py world --pack`. The world runner is
nonactivating and disables mouse capture. Native checks do not inspect animation.
World checks use the real scene/admission path without review-spawn overrides,
but are not a new Generate & play recipe or POI acceptance.

Sleeper assets: `python tools/check_zombie_sleepers.py poses`, `review`, or
`review --missing shin_l`; add `--pack` after a matching export. Rebuild instructions
are in [the editable animation source](../../addons/characters/authoring/Zombie.sleepers.README.md).

Live checks: `python tools/check_zombie_sleepers.py runtime` and `state`, also with
`--pack`. Each launches a second process for restoration evidence. The runtime
fixture uses real characters, awareness, collisions and the contact-noise adapter;
the adapter's input/target acceptance is stubbed to avoid taking the user's mouse.
It is not an end-to-end player input or ordinary generated-world sleeper test.

House checks: `python tools/check_house_sleepers.py`, then `--pack` after a matching
export. These use normal Generate & play and My worlds in owned `SleeperHomes_*`
worlds, then fresh processes for awake/injured restore, clearing and hidden
nonloading admission. Arrival uses the normal teleport/loading path; it is not a
walking/door-interaction playtest. `tests/house_sleepers.gd` checks native keys,
capacity, legacy restoration and the real default plan; `--native-only` is also
run against the release DLL. `tests/house_sleeper_visibility.gd` checks actual
furnished prefab collisions and wall/window admission.

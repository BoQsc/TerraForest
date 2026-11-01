# Gameplay expansion: encounters, exploration and progression

- Status: In progress; native encounters and generated house sleepers, not a completed expansion.
- Updated: 2026-11-01.
- User review: implementation requested; no new asset/animation approval claimed.
- Scope: [full requirements and acceptance](../../docs/GAMEPLAY_EXPANSION.md).

## Images

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

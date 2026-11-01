# Gameplay expansion: encounters, exploration and progression

- Status: In progress; first encounter slice installed, not a completed expansion.
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
The matching installed pack passes 57 pose assertions and 47 ordinary resident
world assertions; this does not test live sleepers. Redistributable content is
476,617,743 bytes. Quiet Mode and the 60-FPS cap are unchanged.

## Remaining / resume here

Connect the authored clips to safe physical transitions, including clearance,
mid-wake hits/amputation/death and suspension. These runtime hooks are not yet
implemented. Add persistent sleepers at authored POIs and ordinary houses; do not
turn a test-only state machine into a claim of playable sleepers. Continue every
remaining row in the linked full contract. Test normal generation, packaged play,
fresh-process save restore, movement/contact and resource budgets. Existing
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

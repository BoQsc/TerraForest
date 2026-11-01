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
Sleeper clips, jogging, new POIs/models and populated-world balance remain unreviewed.

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

## Remaining / resume here

Author seated/lying wake clips and safe physical transitions, including clearance
and missing limbs. Add persistent sleepers at authored POIs and ordinary houses; do not
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

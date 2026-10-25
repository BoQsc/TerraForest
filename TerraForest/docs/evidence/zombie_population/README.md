# World-present zombies — 2026-10-25

The former session-local manager waited 18 active-play seconds, then tried a new
player-relative ring position every eight seconds. That scheduler is removed.
Native seeded population records now own world identities; nearby controllers
load before the loading screen releases input. Terrain sampling is worker-owned,
selection/persistence is native, scene and physics integration remains bounded.

## Verified behavior

- `native_debug/`, `zombie_population_release.*`, `pack/zombie_population/`:
  26 checks each; deterministic whole-world placement, fixed arrival sanctuary,
  focus-independent positions, bounded local query, spatial-index movement,
  anatomical bytes, irreversible deaths, binary roundtrip and atomic malformed
  data rejection. The binary population is 210,032 bytes before archive packing.
- `world_source/` and `pack/zombie_population_world/`: 15 checks each on actual
  temporary seed-1703 terrain; first-playable-frame inhabitants, independent
  awareness, initial safety distance, immediate death record, no timed refill,
  injured/dismembered survivor reload, no duplicate/resurrected identities,
  180 m destination travel and return. Loading gates include inhabitants.
- `disk/write/`, `disk/read/`, `disk/runs.json`: separate OS processes against one
  disposable compound save; 7 checks each. Population deaths, exact body/limb
  health and corpse loot restore together. The test save and sidecars are archived
  in `reports/zombie_population_disk/save/`; no existing user save was opened.
- `no_zombies/`: loading completes with no controllers or population allocation.
- `awareness/`, `anatomy/`, `behavior/`, `encounters/`, `navigation/`,
  `world_combat/`, `character/`, `character_world/`: targeted regressions pass. These do not replace
  the broader navigation acceptance gates.
- `pack_smoke.log`: exported game startup passes. Packaged/source runtime hashes:
  debug `74432c13039947353c90935cbe71ae4b8f403601735bdbb4f91159c1d26c7423`;
  release `80024087ad9b1bcbf8c6cc6cbbfde1d2c16f05b06ba8c2ccafda5204f14c043e`.

## Corrected failures and visual inspection

`failed_crawler_restore/` retains the initial failed prone-state assertion.
The first correction set the capsule/state but left the mesh blending from
standing; a rendered image exposed that mismatch. The final test also measures
the actual head-bone height before simulation, and restore starts the prone clip
without blending. `pack/zombie_population_world/world_resident.png` was inspected:
the saved missing shin/foot is absent and the restored body is already prone.
This capture is not a frame-time benchmark or broad visual-quality approval.

The first isolated release runner timed out because the minimal test project did
not explicitly load its extension; its report path also needed the release
harness convention. Both are corrected and the final release suite passes.
The initial character runner used `failures=0` instead of `CHARACTER_RUNTIME_OK`;
the test itself exited cleanly and the corrected runner passes in `character/`.

## Remaining qualification and return triggers

This change does not simulate dormant zombies across the entire map. It retains
six active controllers, selects at most 32 local candidates, and stores dormant
identities/injuries instead of allocating thousands of physics rigs. Normal
travel skips visible/close new scene admissions; it never moves a world identity
behind the player or schedules replacements after a death.

Population density/pacing and generated settlement/coast/cave coverage need
representative multi-seed playtests before broad acceptance. Existing actor scene
construction takes roughly 130–245 ms per admission in the rendered runs. Initial
construction is behind loading; profile ordinary traversal on lower-end hardware
before claiming smooth streaming, and evaluate bounded reusable/staged rig
construction if those admissions cause visible hitches. Return with traversal
frame-time evidence and an initialization-lifetime design, not a higher actor cap
or a reintroduced time-based spawn loop. Whole-world routes and crawler low-space
traversal still require the gates in `docs/NAVIGATION_STANDARD.md`.

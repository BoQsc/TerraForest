# Narrow-opening mining light — 2026-10-26

## Reproduction and correction

Hidden_Hills, seed 1703, F5 player position (986.2361, 39.93774, 1023.084).
`before.png` / `after.png` use the same saved camera and density with the headlamp
off. They show the nearby saved view, not the exact earlier screenshot framing.
Albedo/normal/torch diagnostics confirm intact surface geometry and textures.

The earlier probe-origin repair remains correct: these origins are already in
air. The twelve sky directions miss narrow, steep openings. A 256-direction
diagnostic sees sky at 30 of 34 nearby vertices that previously received zero.
Reusing a zero-valued canonical probe two metres away also spreads darkness:
air connectivity does not imply the same view of the sky.

- Only near authored density pages (a two-metre query margin), all-blocked
  samples receive 64 additional deterministic, uniformly distributed hemisphere
  rays. Nonzero original samples and open-air fast paths stay inexpensive.
- In these neighborhoods, a zero canonical result cannot suppress an independent
  vertex query. Positive connected canonical probes remain reusable.
- An exact-origin, revision-local direct-mapped cache stores results bit-for-bit,
  including zero. Hash collisions verify the full position before reuse. It has
  32,768 slots, less than 1 MiB allocated, and does not grow with edit history.
- Existing edit invalidation, cancellation and 1,400-step ray budgets remain.
  Work runs during native worker mesh baking, not every rendered frame. No
  shader, brightness floor, terrain geometry or world/save format changed.
- Untouched cave regions retain the previous sampling budget and approximation.
  Existing DLL-identity cache invalidation makes player regeneration unnecessary.

## Verification

- Final source Hidden_Hills: `7cd14639952f459a`; final package:
  `1519ad98557b4e2a`. Wild_Ridge regression: `855d9d37d1084fcc`.
  Each run passes ten captures and original-save hash protection. Final source,
  package and previous-repair images were visually inspected, not merely saved.
- Hidden_Hills baseline/source/package density SHA-256 is identical:
  `bc4cff2357c12fceb71dd8d2e7fe379b45cb9d330ef47adef677b77661eb35cb`.
  Wild_Ridge still matches its original recorded density hash.
- In crop (500,420)–(950,780), maximum RGB <=4 pixels fall from 106,498 to 64.
  `qualification.json` retains multiple thresholds; this is a local comparison,
  not a rule that every cave pixel should be bright. The previously black faces
  now show shaded texture without needing the headlamp.
- Native regression passes 20 assertions at O2 and O3: original 44 buried/49
  zero-air cases, deterministic mesh/save bytes, twelve-ray miss versus 1/64
  refined visibility, exact-point reuse without new rays, adjacent occluded point,
  sealed chamber and closing the shaft again. Existing 044/045 pass 19/21 checks.
- Three saved 32 m patch cold builds: baseline 4.813–4.982 ms, final 5.489–5.600 ms.
  Warm final 3.388–4.720 ms; 2,178 cold rays fall to 26 on repeat. Native mesh-only
  timings, not game FPS or all-world performance guarantees.
- Existing 48-changing-edit native fixture: build p95 2.810 ms, baseline 2.660 ms.
  Untouched cave fixture cold/warm 66.885/23.460 ms; baseline 92.287/33.389 ms.
  These individual runs establish no large observed regression, not a speedup claim.
- Packaged contact mining: 137 assertions / 401 timed operations, unchanged pass.
  Packaged 1,200 mixed edits, held tools and sixteen 8–64 m volumes pass the existing
  frame and response gates. Full frame samples and measurements are retained.
  Runtime p99 is 17.103 ms, maximum 24.309 ms, with no frame over 50 ms.
  Large edits still take hundreds of milliseconds asynchronously; this is not
  an instantaneous editing claim. Matching debug/release DLLs and PCK installed.

## Rejected trials and remaining limits

The unrestricted 64-ray/per-vertex trial improved the picture but failed the
existing probe-reuse check and raised a cold/warm untouched-cave build to
1,442.984/1,133.123 ms. It was rejected, not counted as passing. Restricting extra
work to edited neighborhoods and retaining exact-point results fixes that
regression without relaxing the assertion. Logs retain the failed run.

The initial narrow-shaft test incorrectly expected light at (319,32,320), which
is occluded. That point is now retained as a darkness control; (320,32,320) sees
one of 64 rays and validates the fix. Both the failed fixture and diagnostic
search are retained. No ambient floor was introduced to make the test pass.

Finite sampling can still miss exceptionally small openings. This is not bounced
GI, and sealed chambers remain dark. New false-black reports require a saved
viewpoint and sky/albedo comparison; unchanged caves and multi-hour/other-hardware
performance remain unqualified. User visual approval is separate. Previously
documented render/focus stalls are not closed by this lighting work.
Startup is excluded from the runtime gates and retains four >50 ms frames
(maximum 85.974 ms). The diagnostic's shutdown overlapped early test startup;
the measured editing workload ran after it closed. No startup-speed claim is made.

## Re-run and evidence

`python tools/check_mining_darkness.py --slot Hidden_Hills --pack`

The harness makes an isolated read-only copy, uses a fresh derived cache, and
captures an offscreen viewport in a minimized window. `--pack` checks matching
external native identities. Original saves are never written.

Compile `tests/native/mining_light_regression.cpp` using the pinned compiler with
`-std=c++17 -O2 -ffp-contract=off` (also tested at O3). It includes production core.
Compile `tests/native/mining_light_benchmark.cpp` with `native/core.cpp`; run it
with the retained diagnostic `terrain.bin` and `989 40 1023`. Baseline uses the
core from 72951f9e, not a modified player world. The private density snapshot stays
under ignored reports; only hashes, logs and reviewed images are committed.

`python tools/check_terrain_editing.py --pack --case terrain_contact_mining --case terrain_tools_endurance`

`qualification.json` indexes compressed manifests, logs, raw measurements and
frame samples. Failed trials remain alongside passing results.

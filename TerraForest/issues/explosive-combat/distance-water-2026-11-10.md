# Distant explosions and suspended crater water

- Status: Improved-partial. Distant-explosion package installed and verified;
  water settling remains source-only and disabled by default.
- User review: Not reviewed. Foreground comparisons remain deferred.
- Request: A player must not need to follow ignited barrels; water should settle
  into blast craters instead of remaining suspended.

## Causes and implementation

`combat_world.detonate()` required the entire blast box to pass the player's
actor-collision readiness checks. Those checks include terrain, structures,
vegetation and rocks and follow player residency. Authoritative blast edits
could therefore wait indefinitely despite the barrel already being ignited.
The blast no longer uses that actor-readiness gate. Its native terrain/block
transactions retain their admission and publication checks. No global streaming
radius, resource cap, damage falloff, chain distance, debris count or player
collision check changed.

Water was intentionally static under the October gameplay contract: terrain
invalidation rebuilt occupancy but never redistributed water. The clarified
November request supersedes that behavior for blast-affected water. A native
prototype wakes local regions after accepted blast submission, waits for valid
terrain occupancy, moves integer quantities down and through connected faces,
and sleeps again. It reuses exact terrain/building profiles and existing mesh/query
publication. No per-cell nodes, global fluid tick or source of new water is added.

Settling has fixed region-owned face masks, a bounded region queue, a 256-face
per-call work allowance and a cooperative 1 ms deadline. Remaining faces rotate
fairly, including when a boundary waits for occupancy. Pending regions cannot
retire. New version-11 water snapshots preserve pending work; versions 1–10
remain readable, and snapshots without pending work retain the previous format.
Transfers are committed quantities; restarting a scan after loading cannot replay
a transfer. Pauses, loading and terrain edits suspend the prototype. Its elapsed
time is attributed to `water blast settling` in the existing rolling trace.

**Water settling is qualification-only, disabled by default.** The source runtime
flag is `--blast-water-settling`; it requires the matching new native water DLL.
Installed native water still lacks the prototype: do not enable the flag there.
This is not a completed
fluid simulation or an accepted FPS improvement.

## Evidence

All paths below are relative to the project. No new saved world or source copy
was created. The actual-world test reuses the existing default fixture read-only.

| Check | Evidence | Result |
| --- | --- | --- |
| Remote production combat admission with native barrel/durability stores | `reports/checks/20261110T141236195619Z` | Pass; rejected excavation retains ignition, three-barrel chain and retry idempotence |
| Actual default world, player fixed 160 m away | `reports/checks/20261110T140632912476Z_remote_world` | Pass; actor readiness false, all three explode, terrain/block publication completes, original save hash unchanged |
| Native finite water, save interruption, region transfer, barriers and spill | `reports/checks/20261110T141842204795Z` | 21 checks pass, including an underlying cave blocked by a solid ceiling |
| Actual carved terrain bowl, blast, native meshes and published queries | `reports/checks/20261110T141853998339Z` | Pass; conserved 7,619,860 ml, lowered water, matching published mesh/query revision |
| Receipt-owned region retirement, including pending settling pin | `reports/checks/20261110T141424429614Z` | Pass |
| Deferred water/building admission | `reports/checks/20261110T141436000068Z` | Pass |
| Existing static editing, connectivity, region transfer and store | `reports/checks/20261110T135427385819Z`, `20261110T135438524278Z`, `20261110T135449421713Z`, `20261110T135500580600Z` | Pass; original resting-water behavior unchanged without a blast wake |
| Editor import and new resource identities | `reports/checks/20261110T141328158331Z_blast_import` | Pass |

The old surface regression has the **same 14 failing assertions** in candidate
`reports/checks/20261110T141310964691Z` and installed baseline
`reports/checks/20261110T141414139169Z_water_surface_installed_baseline`.
The baseline also cannot write its legacy `res://reports` output from the mounted
pack; its console preserves the actual assertions. Neither run counts as passing
visual acceptance. Determine whether the fixtures or current surface behavior
need correction before using that suite as a gate.

Rejected development checks remain retained: `20261110T135028378223Z` exposed the
missing pending-queue restore handoff; `20261110T135252689070Z` had a test cleanup
error; `20261110T135758273416Z` caught integer equilibrium rounding;
`20261110T140337915514Z` used an overlong ray outside the existing 5 m query reach.
The corrected checks pass; no runtime reach limit was changed to fix a test.

## Remaining / resume here

- Distant-explosion installation is complete. Evidence is under
  `reports/checks/20261110T142239894838Z_remote_package`: 82 packaged combat-state
  checks pass; `combat_remote_world` passes all three explosions with a stationary
  player 160 m away, using installed native libraries and an unchanged fixture
  save. The actual installed executable passes startup smoke only. The dense
  lighting scan assertion fails identically in baseline and candidate (1/36);
  retain that failure rather than counting it as a passing regression gate.
  Installed PCK SHA-256:
  `d98909526e3840637e0996151724574dab0bf89643671b548f649e38c4f19c40`.
  The predecessor is hash-verified in `previous_package.archive.json`; staging
  is removed and all installed native hashes are unchanged (`installed.json`).
- Qualify water cost separately from intentional waits and scheduling stalls.
  The first whole-cell scheduler took up to 3.077 ms. The face scheduler reduced
  fixture work from 128,000 to 58,952 operations, with the final observed maximum
  1.273 ms. Another run reached 0.586 ms, while earlier runs reached 2.224–3.664 ms. A cooperative deadline
  is not proof of a hard bound. Resume with per-face CPU/scheduling attribution,
  then resumable or worker preparation if an indivisible operation exceeds budget.
- Source follow-up caches immutable floor moments within each face solve,
  retaining exact clipping, iteration order, rounding and quantities. The native
  profile probe passes 16,896 exact volume/head comparisons, including fragmented
  terrain contacts. Unprofiled crater totals improve from 61,866/68,280 us
  (`20261110T142952460141Z`, `20261110T143009316158Z`) to 39,960/41,755 us
  (`20261110T143331301492Z`, `20261110T143347578481Z`), about 37% less total work.
  Candidate maximum calls are 956/1,120 us: the cooperative 1 ms gate is still
  not a hard bound. All final snapshots hash to
  `850ec06403d77f966fe534cd67074dadf4bb47e7e9cc584d120787a042bcb46e`, conserving
  7,619,860 ml with identical 4,376 transfers and 58,952 scheduled face steps.
  The 21 semantic checks pass again in `20261110T143429664322Z`.
- Optional face profiling is off by default. Profiled candidate total is
  47,867 us (`20261110T143408600594Z`), approximately 17% above the two-run
  unprofiled mean; this small, noisy sample does not isolate observer overhead.
  Worst measured face is 772 us. These are wall-clock timings, not thread CPU
  attribution, frame headroom or proof of normal-gameplay stability.
- Shallow-water rendering is a concrete enablement blocker: the current surface
  lattice samples at 25 cm spacing with a 12.5 cm offset. A 4 mm water film can
  have no interior sample, leaving conserved water without a rendered/query
  surface. The existing native sampling diagnostic now covers that exact lattice:
  `reports/water_surface_sampling.log` records 984/1,000 missing 4 mm film phases
  and 36,504 passing isolated exposed-sheet height cases. The latter are not
  integrated topology or visual acceptance.
  Qualify connected exposed sheets, shores, stacked water and building contacts
  before replacing that representation; do not delete small quantities, add fake
  thickness or globally increase sampling density to conceal it. Matching
  mesh/query revisions alone do not prove all finite water is represented.
- Exercise water against dense buildings, slopes, caves, ocean streaming edges,
  concurrent bucket edits, pauses and interrupted compound saves. Full native
  region limits are retained; unavailable/deferred neighbors retain quantities
  and pending work, not pretend completion.
- Verify actual world water visuals/contact behavior and foreground installed
  gameplay when comparisons resume. No new screenshots were captured; native mesh/query checks do not claim
  user visual approval. Existing images in the main issue remain historical.
- The distance test covers resident authoritative barrel records outside actor
  readiness. Chains entering completely paged-out model regions still need a
  separate residency/ownership audit; this is not unlimited remote simulation.
- The 256-barrel next-tick and stable 60 FPS/headroom contracts remain open.

## Reproduction

Use `tools/run_godot_check.py` with `combat_remote_blast`,
`water_blast_settling`, or `water_blast_terrain`, `--headless --require failures=0`.
`combat_remote_world.gd` uses the existing fixture and must be launched offscreen
and nonactivating while foreground checks remain deferred; its exact command is
in the retained run manifest. Do not generate a replacement world for a label.

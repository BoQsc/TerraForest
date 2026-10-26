# Terrain editing reliability and endurance — 2026-10-26

Latest follow-up: [native vegetation page retirement](vegetation_pages/README.md)
qualifies the previously failing 16 ms maximum-brush vegetation gate in finite
source/packaged tests (11.679–13.014 ms), with a passing focused 4,800-edit run.
Focus-switch/presentation stalls and older fixture failures remain explicitly
tracked there; historical failures below are retained, not retroactively passed.

## Reproduced defects and fixes

- ALT and detailed terrain controls offered a 0.25 m brush, below the native
  0.5 m minimum. Both controls now use the supported minimum.
- An ordinary rejected stroke or full submission queue disabled the terrain
  world. Audited atomic commands now recover only when the entire group's native
  revision is unchanged and authoritative storage has no read failures. Dirty
  stamps and pending state roll back; the next valid stroke remains usable.
  Invalid curved profiles and out-of-world strokes are covered. Partial groups,
  corrupt storage, malformed replies and unknown failures still protect saves by
  failing closed; this is not a new whole-batch rollback guarantee.
- Injected allocation failures exposed five exact-state rollback failures in
  voxel blocks and paid terrain stamps. Column capacity is now reserved before
  insertion, membership changes only after insertion succeeds, and fixed replies
  for commands 3/38 are reserved before mutation. Successful terrain/receipt
  fixture hashes remain unchanged. All 704 allocator attempts pass, including
  255 forced failures and zero retained native allocations.
- Targeted 16 m mesh scheduling was restricted to the optional regional renderer.
  The ordinary renderer now uses the same bounded target priority. Queued
  mutation/save barriers and the two-tile interactive limit remain intact.
- Relocating during editing retired all old ground-cover owners in one frame.
  Retirement now performs at most two native owner removals per frame with a
  2 ms soft budget; returning to an owner cancels its retirement. One native
  removal is indivisible, so 2 ms is not a hard upper bound. The traced ground
  stage fell from 42.39 ms to about 2 ms at the reproduced jump.
- Development toolbelt refresh drew inventory icons/styles and immediately
  cleared them to draw tool names. It now chooses one presentation path. Traced
  tool selection fell from 22.55–26.30 ms to 3.86–8.37 ms in the short rerun.

No save format, terrain-generation profile, block grid, player save or brightness
policy changes. Native CPU work remains on the existing worker; no speculative
compute-shader rewrite or new per-frame terrain scan was introduced.

## Coverage

- 7,251 native operations: generators 3/23; sphere/box fills and excavations;
  sampled radii 0.5/0.75/1/4/16/32/64 m; sweeps; materials; page/world/bedrock
  edges; 6,000 mixed edits; 512 paid stamps plus re-mining; maximum road grades,
  shoulders and clearance; invalid inputs; exact binary roundtrips; finite meshes.
- Nonpaged capacity exhaustion rejects without damaging existing bytes and still
  permits edits to resident pages. Paged rejection recovers with a smaller edit;
  a deliberately corrupted isolated region pack remains fatal.
- Existing storage histories, 2,112 distributed edits / 16,896 authored pages with
  a 1,024-page resident cap and exact 32-page cold reopen, mining receipts,
  paid terrain targeting, straight/curved road editors, vegetation continuity,
  terrain/water mining, cancellation and topology checks are exercised separately.
- Rendered endurance uses actual held input for all four developer terrain modes,
  16 large-volume API edits and repeated 400-edit mixed histories, followed by idle
  recovery. Ground cover, trees, rendering and collision are active; zombies are
  deliberately disabled. Maximum-radius edits are measured separately from
  ordinary interactive latency. Global frame accounting includes tool switches
  and phase transitions, not just phase-local samples.

## Performance scope and remaining work

The initial full-ground-cover run failed frame budgets (90 ms relocation and
305/320 ms boundary stalls). Those results remain retained. A 1,200-edit rerun
after the fixes has p99 17.009 ms, maximum 39.130 ms and zero frames over 50 ms,
including switches. This is 1920×1080 Forward+ at full scale, capped at 60 FPS,
on the current RTX 4050 / i5-12450H laptop, not evidence for other hardware.

Final source suite `20261026T072044Z`: 25 passing cases and the explicitly failed
cold-arrival continuity case. The 4,800-edit endurance run retains 13,663 measured
frames including switches: p99 **17.171 ms**, maximum **40.484 ms**, zero over
50 ms. Ordinary edit-publication p95 ranges from **35.52 to 50.81 ms** across
the twelve rounds. Authored pages stay at 966 and mesh entries at 400; engine RAM
still includes growing test trace dictionaries and settling vegetation, so this
is not a claim of flat whole-process memory. The largest volume's publication
takes **918.012 ms** without an equivalent main-thread stall.

The original campaign retained arrival gaps of **289.073 / 83.331 ms** despite
passing frame and post-capture latency gates. The follow-up below fixes a
publication dependency in that generator-1 fixture. The later coarse-column
follow-up also closes the reproduced generated-world reconstruction case. Waiting to obtain
a usable visible target remains included in the 150 ms player-response gate.

Packaged validation: native recovery, paged rejection/corruption, volume history,
paid materials, bounded target ordering and retirement pass. All 54 placement
preview checks pass. The isolated release DLL passes the same 7,251-operation
volume fixture. The final quiet PCK run `20261026T074134Z` passes 37 developer-belt
checks and 1,200 mixed edits: p99 **16.995 ms**, maximum **45.505 ms**, zero frames
over 50 ms; ordinary publication p95 **34.79–35.00 ms**.

Two earlier PCK runs nevertheless contain **105.619 / 81.805 ms** frames, mostly
inside the measured draw span (**101.494 / 76.326 ms**), not the measured terrain
publish or ground-cover stages. Their root cause is not established. A quiet
passing rerun does not erase those failures or prove all stutters fixed. The
latest observer also records focus and pipeline counters; repeated uninterrupted
render/presentation profiling is the return path for this remaining issue.

Maximum 64 m brushes can take roughly a second to publish while frames continue.
Long unsaved histories still have finite pinned-page limits: recovery must not be
described as unlimited editing capacity. Multi-hour runs, colder/larger saved
worlds with entities, multi-seed travel, lower-end/thermal qualification and
unexplained earlier boundary stalls remain open. Return with the retained frame
and stage traces; do not weaken frame/latency gates or treat screenshots as FPS
proof. Visual/player acceptance is separate from these engineering checks.

## Post-travel readiness follow-up — 2026-10-26

Evidence is under `travel_readiness/`; large JSON/CSV traces use gzip. The original
delay reproduced at **294.134 ms**. Native target geometry arrived about 60 ms
after input, but the ordinary renderer withheld it until unrelated siblings
completed. Contrary to the earlier coarse-parent explanation for this particular
fixture, root `(1280,1024,256)` was absent from the initial visible cut.

The production stream now always calls the existing native `coverage_available`
planner. Previously only the experimental regional renderer used that policy.
Ready disjoint tiles can appear in previously uncovered space. An existing
visible parent still stays until its entire replacement is ready; dirty hidden
parents cannot return, a late coarse mesh cannot withdraw active fine collision,
and partial roots do not count as fully loaded. No new mesher, density sampling,
shader, worker pool, per-frame forest scan, save format or generation change.

Unchanged actual-held-input gates, fullscreen 1920x1080 Forward+ / cap 60 on the
current RTX 4050 / i5-12450H laptop:

- Source repeats: first-arrival maximum gaps **107.019 / 108.427 ms**.
- Three packaged repeats: first changes **108.616 / 92.370 / 105.041 ms**;
  second changes **65.221 / 64.873 / 60.879 ms**. All visible-change gaps pass
  150 ms, frame p99 stays below 20 ms and no measured frame exceeds 50 ms.
- Packaged 1,200-mixed-edit / 16-large-volume stress run: **4,781** runtime
  frames, p99 **17.136 ms**, maximum **39.453 ms**, no frames above 50 ms.
  This run uses generator 23 and ground cover; it waits for edit-site readiness,
  so it is not evidence for the separate cold-arrival case below.
- Native planner, real default-stream coverage/physics, complete parent-to-child
  and distant coarsening transitions, worker atomic publication, target queue
  barriers and suspended-upload priority pass in source and the PCK. Restoring
  the original policy makes the new default-stream regression fail nine checks.

The first changed-frame capture shows the local crater while the rest of that
previously unloaded root is still missing; the 500 ms capture shows continuous
surrounding terrain. This is not seamless whole-world teleport acceptance.
Native shared boundary representatives and physical collision on both sides are
tested separately. The visual diagnostic uses intrusive GPU readback and fails
frame gates; it is not counted as a performance pass.

### Retained failure: generated-world coarse owner

A fresh generator-23 / seed-1703 run before the coarse-column fix fails: first change
**243.948 ms**, largest visible gap **320.786 ms**. Frame gates pass. Its first
edit rebuilds the already-visible **256 m** owner `(1280,1024,256)` for
**182.766 ms** on the worker; subsequent early builds reach **223.114 ms**.
Unlike the fixed absent-root case, exposing a fine tile by hiding that parent
would discard existing coverage. This change deliberately does not do that.

The requirement was bounded local replacement of an already-visible
coarse owner, preserving outer geometry, joins, collision and atomic publication.
Do not enable the experimental renderer globally, cut holes, skip distant edits
or weaken gates to claim completion. Return with the retained generator-23 trace
and the existing native regional-owner implementation; require actual-input
first-response/continuity <=150 ms plus distant, collision and rendered checks.
The coarse-column follow-up below meets the reproduced-case requirement; a
Wild_Ridge copy adds saved-world evidence, not all cold-checkpoint qualification.
Long histories and populated travel remain separate. No original save was changed.

Reproduce the unconditioned generated-world arrival (current default):

```powershell
python tools/run_godot_check.py held_mining_flight --timeout 180 --require "bounded observer writer retains all frames and progress reports" -- --world-generator=23 --world-seed=1703 --ground-cover --no-zombies
```

Retained non-passes: `after_2` loses focus/input validity and fails frame p99;
its timing is not acceptance. `pack_report_path_failure` passes game assertions
but three harnesses attempt a read-only `res://reports` mkdir; absolute directory
paths fix those diagnostics in `pack_functional`. Early fixture-development logs
retain a pending-edit staging setup error and an incorrect assumption that legacy
surface-net boundaries lie on a flat grid plane. The corrected fixture compares
shared boundary-cell vertices and published colliders rather than imposing a new
meshing convention. `original_policy_regression` is the intentional red control.
The ordinary generator-1 continuity check now runs in the default regression
matrix instead of requiring an opt-in flag. Reports record first-visible time
separately from maximum gap and identify generator/renderer/ground-cover settings.

## Coarse-column arrival follow-up — 2026-10-26

`coarse_columns/` preserves manifests, compressed measurements/frame traces and
the unsuccessful diagnostics. The default uses native 32 m-wide full-height
columns only inside coarse terrain tiles. Fine 16/32 m terrain is unchanged.
This is not the 512-slab experimental renderer: a 256 m parent has 64 columns,
with the same Surface Nets shared-boundary rules and a distinct cache namespace.
Edits preserve unaffected geometry/collision and publish replacements atomically.

The first unconditioned generated-world runs passed, but the distant parent had
not yet loaded. Those passes did **not** prove existing-parent locality. The new
`--coarse-arrival` fixture waits for that distant coarse parent at the original
player position, then teleports and immediately holds the real tool. It does not
wait for fine destination geometry. An assertion requires a 256 m edit result
during the first burst; the original 150 ms input-to-first-draw / maximum-gap and
20 ms p99 / no >50 ms frame gates are unchanged.

That stricter test exposed a second defect: integer rounding selected a neighbour
whose affected-column list was empty. Empty was interpreted as a full build,
causing 64 columns to be loaded/rebuilt and gaps over 150 ms. Empty selections now
explicitly retain geometry and advance the stamp, without reconstruction or disk
reads. A native-worker regression verifies all retained attributes against fresh
geometry, not just timing or node counts.

Current-laptop results, fullscreen 1920x1080 / full scale / cap 60:

| Fixture | First response ms | Maximum visible gap ms | Frame p99 ms | Maximum frame ms |
| --- | ---: | ---: | ---: | ---: |
| Source existing-parent, three runs | 81.125–85.199 | 100.371 | 17.778 | 28.405 |
| Packaged existing-parent, three runs | 82.227–98.075 | 109.311 | 17.983 | 36.875 |
| Source Wild_Ridge read-only copy | 88.822 | 100.129 | 17.531 | 28.042 |
| Packaged Wild_Ridge read-only copy | 82.999 | 100.227 | 17.883 | 30.330 |
| Packaged unconditioned arrival, three repeats | 84.501–104.220 | 104.220 | 18.436 | 35.762 |

Every second arrival also passes. First source unconditioned generated-world
repeats pass at 92.320–108.525 ms. Save-copy manifests hash every copied source
file before/after; the original Wild_Ridge is unchanged. These tests use its real
saved terrain/history but keep entities disabled and do not cover arbitrary cold
histories, seeds or hardware.

Geometry coverage includes generators 1/23, excavation, world borders, LOD 1/2/4/8,
exact fine-mesh equality, coarse/fine edge equality, native cancellation and
unchanged authoritative bytes. Cache tests compare all geometry/material channels
after cold, warm and restarted workers. A coarse corner edit replaces 4 columns
and retains 60; the rounded empty halo retains all 64. Debug and release real-worker
tests cover old/new physical collision, preemption, atomic publication and distant
coarsening. The source 4,800-edit run passes 13,863 frame samples (p99 17.405 ms,
maximum 47.566 ms), with ordinary edit p95 35.509–50.840 ms; this preceded the final
empty-selection fix. Final packaged qualification is recorded separately.

The final packaged 4,800-edit run passes 14,046 runtime frames including switches:
p99 **17.661 ms**, maximum **33.760 ms**, zero frames over 50 ms. It also completes
16 maximum-volume operations (4,816 API commands total). Ordinary edit p95 ranges
from **35.461 to 51.285 ms**. At recovery it reports 326 mesh entries, 966 authored
pages and 179,635,336 cached terrain bytes; this is finite-run accounting, not a
whole-process memory plateau claim. The packaged generator-1 arrival also passes
at **107.508 ms**, preserving the earlier ~289 ms fixture fix.

The final packaged matrix is **11 passes / 1 non-pass**, not a clean suite:
unconditioned generator-23 arrival meets every 150 ms response gate (106.539 ms
maximum gap) but misses frame p99 at **21.014 ms**, with a **24.321 ms** maximum
and no >50 ms frame. One sample is process-span-heavy, another draw-span-heavy;
terrain staging peaks at 4.121 ms, so this is not evidence that the old whole-parent
rebuild persists. The frame-pacing cause remains unassigned. Keep profiling it
with native/render/OS scheduling traces rather than weakening the 20 ms threshold
or describing this matrix as all-green.
Three subsequent fresh-cache unconditioned PCK repeats pass every unchanged gate;
they establish repeatability, not an explanation or erasure of that frame miss.
The archive index records source directories and SHA-256 of every uncompressed
artifact. Debug/release DLL hashes match the installed pack-side libraries.

Retained non-passes include the all-LOD regional prototype's 60-second initial
readiness timeout, the first coarse fixture's incorrect refill-count assumption,
three existing-parent gaps before the empty-list fix, and the original saved-copy
gap. One pre-fix arrival also has a 68.141 ms process-span-heavy frame; its root
cause is not independently established. The maximum populated vegetation check
still takes 17.973 ms against its 16 ms gate (71 functional assertions pass).
Those failures are not erased by later passes. Broader render-stall investigation,
multi-hour/populated travel, large-history paging and maximum-brush vegetation
publication remain open; this closes the reproduced arrival bottlenecks only.

```powershell
python tools/check_mining_arrival.py --pack --coarse-arrival --repeat 3
python tools/check_mining_arrival.py --pack --slot Wild_Ridge
python tools/check_mining_arrival.py --pack --coarse-arrival --visual
python tools/check_terrain_editing.py --pack --case held_mining_flight --case held_mining_generated --case held_mining_coarse
```

`--whole-patch` retains the old reconstruction path for comparison. Visual GPU
readback is diagnostic, not a performance run. New tests use temporary worlds or
explicit copies, never the original save; player preferences are not written.

Inspected packaged captures show the first crater at 89 ms and its continued
excavation at 503 ms while the surrounding target terrain remains present. The
second arrival also visibly excavates the grass surface. Distant unloaded terrain
is visible **before and after** mining; this is not seamless whole-world teleport
or world-quality acceptance. The readback run fails both p99 frame gates
(32.275/33.402 ms), as expected from intrusive capture; only separate normal runs
qualify performance. No image was used as FPS evidence.

## Visual and harness checks

The inspected large excavation and mixed-material volume remain visibly intact.
The immediate large-edit capture shows old tree poses while support queries are
pending; the separately settled capture confirms those unsupported trees are
removed after reconciliation. That run was not atomic with terrain publication;
the subsequent per-instance support change closes this resident-vegetation delay
(see `../vegetation_terrain_support/README.md` for current checks and remaining
performance limits). The steep-slope regression preserves all 60,882 cover
records, with no new grass/tree identities or changed distant transforms. The
images are synthetic stress geometry, not proposed world art or house redesigns.

Five supplemental headless checks cover legacy road beds, site cancellation,
no-op sections, full lot preparation and suspended mesh preparation. The older
road-editor fixture now checks the actual docked workspace against the belt,
not its obsolete standalone panel. The developer-belt fixture includes the
existing Graphics page and explicitly grants the temporary owned building item
before equipping it. No player inventory is touched.

Retained unsuccessful diagnostics include a six-failure legacy
`player_hud_smoke` run: it still expects the repair hammer to build and building
controls inside ESC. That older fixture is not rewritten here; the current
developer-belt and placement checks cover the changed presentation paths.
Earlier water/vegetation runs lacked their required fixture flags; earlier
endurance runs omitted ground cover and do not qualify grass performance.
The first PCK graphical run also tried creating a virtual `res://reports` directory;
the test output now uses an absolute path. Visual readbacks are kept outside
performance qualification rather than relaxing the 20/50/150 ms gates.

Both native variants and the resource pack are installed with matching hashes.
Export startup passes; duplicate-UID warnings originate in retained report
snapshots, not the new source sidecars. All new test UIDs are committed.

## Reproduce

```text
python tools/probe_terrain_edit_atomicity.py
python tools/check_terrain_editing.py --native-only
python tools/check_terrain_editing.py --extended --with-known-continuity-check
python tools/check_terrain_edit_release.py
python tools/check_terrain_editing.py --pack --case terrain_edit_recovery --case terrain_edit_volumes
python tools/run_godot_check.py terrain_tools_endurance --require "TERRAIN_TOOLS_ENDURANCE failures=0" --timeout 300 -- --world-generator=23 --ground-cover --no-zombies --terrain-soak-rounds=1 --terrain-tools-visual
```

Continuity cases now run by default; `--with-known-continuity-check` is a compatibility
alias. Any failed gate keeps the runner nonzero. Visual mode is not a performance run.
Every launcher selects an isolated temporary world/cache, not a player's save.
Logs, manifests, compressed measurement/frame traces and inspected images are
retained alongside this file; exploratory failures are not counted as passes.

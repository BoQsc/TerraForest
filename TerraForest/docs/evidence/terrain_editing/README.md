# Terrain editing reliability and endurance — 2026-10-26

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
publication dependency in that generator-1 fixture, but does not close the
separate generated-world coarse-owner reconstruction problem. Waiting to obtain
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

### Still open: generated-world coarse owner

A fresh generator-23 / seed-1703 run with ground cover still fails: first change
**243.948 ms**, largest visible gap **320.786 ms**. Frame gates pass. Its first
edit rebuilds the already-visible **256 m** owner `(1280,1024,256)` for
**182.766 ms** on the worker; subsequent early builds reach **223.114 ms**.
Unlike the fixed absent-root case, exposing a fine tile by hiding that parent
would discard existing coverage. This change deliberately does not do that.

The remaining requirement is bounded local replacement of an already-visible
coarse owner, preserving outer geometry, joins, collision and atomic publication.
Do not enable the experimental renderer globally, cut holes, skip distant edits
or weaken gates to claim completion. Return with the retained generator-23 trace
and the existing native regional-owner implementation; require actual-input
first-response/continuity <=150 ms plus distant, collision and rendered checks.
Cold persisted checkpoints, long histories and populated travel remain separate
qualification. No player saves were used or changed.

Reproduce the remaining case:

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

The optional known-continuity case intentionally keeps the runner nonzero while
that gate fails. Visual mode includes GPU readback and is not a performance run.
Every launcher selects an isolated temporary world/cache, not a player's save.
Logs, manifests, compressed measurement/frame traces and inspected images are
retained alongside this file; exploratory failures are not counted as passes.

# Vegetation publication and travel follow-up — 2026-10-26

## Native change

Removed vegetation identities, picker entries and visible instances still disappear
in the same terrain publication. Empty render pages hide immediately; only their
resource destruction is deferred. Each collection drains hidden pages with a
350 microsecond soft budget per frame. One resource destruction is indivisible;
this is not a hard frame-time guarantee. The existing pool retains at most sixteen
empty nodes. Partially edited pages update immediately, preserving every survivor's
transform and appearance age.

Hidden pages remain charged against the same GPU byte/page limits until actually
released. Admission backpressures against active plus retired ownership. Rapid
travel return, incremental reset, explicit clear and reduced-cap reconfiguration
are tested. Point-only slot/fade lookup tables now use native hash maps; sorted
authoritative placements, serialized bytes and stable IDs remain unchanged.
Whole removed groups erase their membership tree once rather than searching it
for each root. Empty-page retirement skips a redundant missing-birth lookup only
when the removal transaction has already pruned those appearance records.

`vegetation_page_retirement` verifies nineteen ownership/visibility/reset assertions
in both debug and isolated release builds. Existing continuity/fade tests inspect
visible pages, not deliberately hidden retired buffers. They retain exact survivor
and fade equality; the new test separately asserts hidden-byte ownership and caps.
Release static-placement checks cover 235 assertions, including 100,000-record
paging and sorted identities; incremental retirement passes 56 assertions.

## Diagnostic scope

The cleanup-only candidate still failed the unchanged 16 ms maximum-publication
gate at 16.309 ms for 18,517 instances. Adding average-constant-time slot/fade lookups
reduced the next source measurement to 12.912 ms; all 72 integrated assertions
passed. Preserve the earlier failure rather than treating deferred deletion alone
as sufficient. Complete terrain publication is a separate, much longer operation.

Slow-frame records now include native cover selection, upload and retirement,
ground/water processing, measured terrain/world stages and pipeline counters.
These are correlation measurements, not proof of an OS/driver stall's cause.
No performance threshold, render resolution, terrain generation or save format
was relaxed. Tests use disposable worlds; player saves remain untouched.

## Final qualification

- Final source maximum-brush publication: **11.685 ms**. Two packaged repeats:
  **13.014 / 11.679 ms**, 18,517 sampled instances, all **72 assertions pass**
  each time against the unchanged 16 ms gate. Small tool publications are
  **0.222–0.513 ms**. Complete maximum-volume terrain publication still takes
  **922.646–1,008.055 ms**; the 11–13 ms number is only its vegetation commit.
- Focused packaged 4,800 mixed edits plus sixteen large volumes: **13,697 runtime
  frames**, p99 **17.987 ms**, maximum **33.960 ms**, zero frames over 50 ms.
  Ordinary mixed-edit publication p95 is **35.324–50.120 ms** across twelve rounds.
- Final packaged ordinary/coarse-parent arrival cases pass all unchanged gates:
  first change **104.790 / 72.955 / 88.661 / 57.093 ms**; maximum visible-change
  gap **104.790 ms**; frame p99 at most **17.377 ms**. No waiting for fine terrain
  readiness was added. Earlier three-repeat runs of each arrival fixture also
  passed, but do not replace final-build checks.
- Final debug and release ownership tests pass; the final release rerun retains
  all 235 static-placement and 56 incremental-retirement assertions. Six Python
  launcher checks pass. PCK export/startup succeeds with fourteen matching native
  libraries. External test scripts resolve libraries from the project root, so
  packaged runners now reject differing source/dist DLL sets before launch and
  record all matching hashes.

Raw manifests, compressed logs, frame traces and results are retained in
`final_source`, `final_pack`, `final_repeat`, `final_endurance`, `final_release`
and `qualification.json`. Older manifest open-work notes describe status before
this qualification; their original bytes are retained rather than rewritten.

## Remaining limits and failed evidence

- `retained_pack` preserves the intermediate **21.290 ms** vegetation miss, a
  **20.287 ms** coarse-arrival p99 miss, and a **66.552 ms** endurance frame. The
  latter contains **62.904 ms** in draw/presentation and **3.360 ms** in process,
  with negligible native-cover work; focus was lost. The user confirmed switching
  windows. A separate approximately 50 ms draw stall occurred while the sampled
  focus flag was still true. Focus changes do not prove the cause of every stall.
  The focused final rerun passes; it does not erase these failures or establish
  a universal zero-stutter guarantee.
- Windows Performance Recorder CPU tracing was attempted, but Windows refused
  the profiling policy (0xc5585011). No policy/security settings were changed and
  no trace session started. OS/driver scheduling attribution remains unproven.
  Return on a focused reproduction or when a permitted platform trace is
  available; correlate it with the retained frame/stage/native timings, then
  rerun unchanged 20/50/150 ms gates before closing this issue.
- Legacy `vegetation_collect_continuity` fails its owner-settling deadline with
  both this DLL and the prior `5b17241f` DLL. Its default-generator invocation also
  uses an unsupported legacy layout query. `vegetation_edit_world` repeats the
  same four failures with both DLLs: settling, unowned paid brick placement,
  resulting exclusion, and an obsolete expectation that mining preserves all
  authored plant records. Its unaffected-rendered-neighbour checks pass. These
  fixtures need updating to current inventory/removal contracts; they are not
  counted as passes here. The isolated baseline control additionally failed its
  old virtual `res://reports` output path and timed out; logs retain that failure.
- The finite current-laptop gate is qualified, not multi-hour endurance, every
  hardware/seed, focus-switch presentation, or overall world-quality acceptance.
  New source and packaged support tests cover current removal semantics; they
  do not silently waive the legacy fixture failures.

## Reproduce

```text
python tools/check_terrain_editing.py --pack --extended --case vegetation_page_retirement --case vegetation_terrain_edits --case vegetation_edit_continuity --case terrain_tools_endurance --case held_mining_generated --case held_mining_coarse
python tools/check_mining_arrival.py --pack --repeat 3
python tools/check_mining_arrival.py --pack --coarse-arrival --repeat 3
python tools/test_native_release.py --godot "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot Engine.exe" --addon structures --test vegetation_page_retirement
```

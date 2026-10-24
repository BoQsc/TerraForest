# Grass continuity during placement and mining

2026-10-24. The user narrowed recurring grass/vegetation blinking to placement
and mining. The earlier pickup fix (81926a40) only covered one removed instance.
Bulk removal, same-group support-height updates and insertion still released
visible pages and queued replacement uploads. A surviving plant could therefore
disappear for several frames even though its authored identity remained present.
The earlier fade check waited eight frames, and collection tested single removal;
neither covered this edit path. This was incomplete coverage, not evidence that
the single-pickup correction had been undone.

## Native correction

Appearance-faded streamed collections now retain compact page membership through
live upsert/removal. Bulk exclusions swap removed identities with tail members
and refresh only resident pages whose membership actually changes. Support-height
updates refresh the affected resident pages within the same scene call. Every
survivor retains its original fade birth. Appends preserve existing slots and
partial pages; new pages or growth wait for normal budgeted admission. An admitted
partial page is replaced within one tick, never left absent in the queue.

The synchronous path never adds resident payload for an append. Removal shrinks
or preserves existing payload. Page/byte ceilings remain authoritative. Immediate
edit work is separate from background upload-per-tick limits: work scales with
touched resident pages and local 32 m groups, with bounds/index maintenance over
their authored records. This is not a hard frame-time deadline. Snapshot restore,
asset replacement, generic non-faded model collections and collision-only trunk
batches retain their established rebuild behavior. No shader, density, mesh,
damage, inventory or world-save format changed.

## Verification

- `native_debug` and `native_release`: 27 graphical GPU-readback assertions over
  900 initial records, 128-record pages and a strict one-page background upload
  budget. Check immediately and on each following frame after bulk exclusion,
  80 support-height updates, appends and cross-group migration. Also cover original
  appearance ages, partial residency, byte caps, full cleanup and same-identity
  snapshot restore. Release loads the release DLL in an isolated clean project.
- `world`: 20 actual-world checks use the paid brick coordinator, actual block
  exclusion/removal, native terrain excavation and asynchronous density/support
  publication. Three temporary authored clumps at a natural support point force
  bulk exclusion. GPU packets for 888 unaffected grass clumps in the same spatial
  group are checked on every observed rendered frame: 94 frames, zero gaps or
  changed fade ages. Durable authored records remain unchanged. This calls the
  production edit coordinator, not an emulated right-click/aim fixture.
- `packed_world`: repeats all 20 world assertions against the exported PCK and
  final external native libraries, with an external test script and explicit
  writable evidence directory. Command/PCK/engine/test/native hashes are retained.
- `pickup`: the existing single-removal continuity check still passes.
- `fade`: native appearance/byte accounting and production shader age/distance
  coverage checks pass, including the original opaque dither fade behavior.
- `ground_stream`: 156 existing publication, exclusion, identity, retry, stale
  result, picking, support, interaction and staged reset checks pass.
- `forest_support`: 19 existing tree/trunk support, unchanged-row transition,
  stale-result, empty-owner retirement and reconciliation checks pass.
- `static_models`: 235 existing native placement/history/collision/dense-page/
  streaming assertions pass. These generic-model checks are headless and do not
  supply GPU image acceptance; the continuity tests above are graphical.

Both native structures libraries were rebuilt from the final sources with pinned
Zig and prebuilt godot-cpp. Build hashes, export/startup logs and source hashes are
retained. The source world run precedes the final isolation of restore semantics;
the final packed-world check repeats that edit sequence with the final libraries.

Source and packed 1920x1080 captures show the actual forest, one brick replacing
the overlapping test clumps, restoration and the excavated surface. The source
captures were inspected; packet observations, not these few stills alone, establish
the measured continuity. Wind was frozen for this diagnostic. Readback/screenshots
add overhead, so these are functional checks, not sustained FPS/thermal evidence.

The 900-record debug fixture observed scene-call times of 740 us for five bulk
removals (40,896 payload bytes refreshed), 333 us for 80 support updates (16,384
bytes), 261 us for appending 20 plants (zero immediate upload) and 497 us for one
cross-group move (9,344 bytes). The release sample is also retained. These finite
scene-call timings exclude readback and do not measure GPU completion, complete
frame cost or a latency guarantee.

```powershell
python tools/build_native.py --addon structures --target all
python tools/run_godot_check.py vegetation_edit_continuity --timeout 35 --require 'failures=0'
python tools/test_native_release.py --godot 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot Engine.exe' --addon structures --test vegetation_edit_continuity
python tools/run_godot_check.py vegetation_edit_world --timeout 180 --require 'failures=0' -- --gameplay-construction --ground-cover
python tools/run_godot_check.py static_placements --timeout 90 --require '"failures":0' --headless
```

## Retained failures and limits

- `headless_readback`: the first diagnostic used the dummy renderer, which cannot
  provide the intended MultiMesh GPU readback. It failed initial residency and
  later indexed missing witness data. The test now explicitly requires graphics.
- `before_fix`: rendered baseline confirms missing survivors immediately and
  across several frames after bulk exclusion, support edits and insertion. The
  initial fixture then assumed insertion had fully settled and indexed an absent
  record. That fixture sequencing error is retained; a separate settling wait now
  makes the remaining migration checks safe. The observed continuity failures are
  not counted as passing because of that fixture error.
- `restore_candidate`: an intermediate implementation retained old GPU transforms
  on explicit snapshot restore. Its new regression failed. Continuity is now an
  explicit local-edit option; restore keeps its original rebuild semantics.
- `forest_stub`: the older tree-support fixture omitted the backend generation
  profile now required by candidate generation. Fifteen earlier assertions passed,
  then its stub errored. Supplying that profile lets all 19 assertions run.
- `static_completion_token`: all 235 assertions passed, but the invocation required
  the wrong text format. The rerun uses the actual JSON completion token and passes
  both assertions and launcher diagnostics.

This closes the reproduced local edit-induced page gap. It does not certify every
vegetation/shadow flicker source: moving-view shimmer, distant/budget-pressure
continuity, edit-storm frame cost and general world-art/performance acceptance
remain tracked in WORLD_FOUNDATION_STATUS.md. Future reports should retain their
trigger and first failing frame against these witnesses rather than checking only
membership after streaming has settled.

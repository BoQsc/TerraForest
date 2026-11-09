# World/player performance foundation — 2026-11-09

Status: implemented improvements; **stable 60 FPS with headroom is not achieved**.
This continues the [fresh-default investigation](rolling-trace-2026-11-09.md).
Original new code is 0BSD. Existing notices remain. The generated debris catalog
is original CC0 with its own source/engine/hash receipt; no new dependency.

## Changes and measured limits

| Path | Change | Evidence / practical limit |
| --- | --- | --- |
| First-person arrival | Activate the same depth-protected materials behind the opaque loading cover, before control release | Matched default-world release **223.587 → 26.603 ms**; draw **160.549 → 9.513 ms**. Covers the tested existing-photo arrival, not every cold driver/material or newly generated photograph |
| Existing arrival photograph | Decode/validate on a worker during loading, keep corrupt/missing-photo recovery | Release request **46.868 → 0.002 ms**. The first-ever clean screenshot still requires a GPU readback |
| Parked Ranger prototype | Optional adapter preparation hooks move receipt hashes/resource loading to a worker; readiness polls before activation | Prior prototype **81.998 ms** (distant parts 81.004); combined run's prototype stage maximum **4.014 ms**. Independent providers retain their normal parts and no-op hooks; tracing is optional |
| Zombie resource | Built-in model becomes an explicit threaded startup dependency; separate resource/instantiate/attach timings | First loading population hitch **190 ms → about 61 ms** in these runs. Remaining anatomy/attachment work is synchronous; admission and pursuit are not closed |
| Destruction transaction | Native compare-and-remove for up to 64 expected cells with revision/admission checks; blast chunks remain 24 and collapse chunks 12 | 64-cell workload publishes **3**, previously **64**, invalidations. Rejected batches retain cursor/damage/debris; undo history is cleared before publication |
| Debris collision | Offline binary catalog preserves the exact old convex-decomposition recipe for all 704 supported poses; bounded mesh/material sharing | **56,470 bytes**. Actual-world destructive calls **0.795–2.125 ms per batch**, versus **1.50–2.40 seconds** for the controlled per-cell/decomposition policy. No runtime decomposition for supported poses |
| Water save capture | Native copy-on-write region arrays; snapshot transfers handles and sums/encodes on the existing save worker | 1,024-region capture **2.652–9.196 → 0.248–0.328 ms**; concurrent edits preserve byte-identical frozen output. Same archive format, water quantity and 128 MiB pending cap |

The explosion result is a substantial source fix, not a full-frame guarantee.
The control uses the new removal primitive per cell and deliberately regenerates
the old convex resources; it excludes old undo-allocation cost. Two ABBA cycles
use identical 64-cell wood structures and 24-candidate slices in the actual world.
Main-thread batch work falls from seconds to milliseconds, but whole 64-cell
completion still spans physics frames (19–68 ms in the optimized samples).
No debris cap, lifetime, mass, CCD, impulse, geometry, damage falloff or settings
was reduced. CPU decomposition was the dominant discovered cost; moving this
immutable work offline is preferable to repeating it on a GPU during explosions.
[Godot's implementation](https://github.com/godotengine/godot/blob/master/scene/resources/mesh.cpp)
confirms that `create_convex_shape(true, true)` requests convex decomposition.
No upstream implementation was copied into project code.

## Reproducible evidence

Reports are local retained artifacts; failed attempts are retained too.

- Combined fresh-default clone: `reports/performance_changes/20261109T084818225689Z_combined_changes`.
  Continuous observation plus deduplicated triggered windows, 1080p Vulkan
  Forward+, i5-12450H / RTX 4050 Laptop, unchanged Quiet Mode/settings.
  Gameplay triggered-window p99 **26.479 ms**, maximum **91.449 ms**;
  root GPU mean **15.027 ms**, p99 **16.661 ms**. No 60 FPS qualification.
  Functional save/exit succeeded but the strict harness rejected one anonymous
  ObjectDB leak, also seen before these changes. It remains open.
- Water before/after: `reports/checks/20261109T084003030682Z` and
  `reports/checks/20261109T084202334145Z`; eight iterations each.
  Extended debug/release storage/contact/ocean/transfer/snapshot suite:
  `reports/water_patch/20261109T085539656865Z`.
- Actual compound water authoring, bucket, mining, partial-building and disk
  reopen: `reports/performance_changes/water_compound_graphical_20261109T090956Z`.
  All assertions pass. The retained external driver only adds offscreen ownership.
- Destruction before binary bake: `reports/performance_changes/destruction_20261109T090105Z`.
  After bake: `reports/performance_changes/destruction_baked_20261109T090750Z`.
  Both pass functional assertions. The screenshot is of the deliberately slow
  final control; its FPS counter is **not** evidence of optimized gameplay speed.
- Geometry parity: `reports/checks/20261109T090650617860Z` compares exact sorted
  convex vertices for cube, stairs, sphere, cylinder and modular shapes/rotations.
  Native edit contracts pass debug/release in `reports/block_cell_patch/20261109T085613752904Z`.
- Real combat: `reports/combat_world/20261109T084303350052Z`, 51 creation + 12 reopen
  assertions, including barrels, firearms, zombies and interrupted blast recovery.
  Blast image inspected; later binary geometry has its separate exact parity check.
  Installed executable repeats all **51 + 12** checks successfully in
  `reports/combat_world/20261109T091611473955Z`; its blast image was inspected.
- First-person close-wall, forest, lighting and world parity:
  `reports/checks/20261109T083024964303Z_first_person`; images inspected.
  Existing/corrupt photograph checks: `reports/checks/20261109T083439947845Z`.
- Independent vehicle providers: `reports/checks/20261109T085538372115Z`.
  Real prototype: `reports/checks/20261109T084256485580Z`.
  Zombie aggression/sleeper behavior: `reports/zombie_aggression/20261109T085007957459Z`.

### Final source and installed checks

- Source normal gameplay save: `reports/performance_changes/20261109T091958603709Z_save_capture_attribution`.
  Strict pass, including clean exit. Save capture stage **8.042 ms**, component
  capture **7.971 ms**, water **0.879 ms**, structures **5.873 ms**. Triggered
  gameplay p99 **30.172 ms**, maximum **34.573 ms**. This is a short repeated
  fixture, not proof of sustained or dense-world headroom.
- Final installed trace: `reports/performance_changes/20261109T092346795985Z_final_installed_capture`.
  Requested gameplay save completed successfully, shutdown publication verified,
  and zero pointer captures. **Strict FAIL:** three anonymous ObjectDB instances
  leaked at exit. An earlier installed run (`20261109T091458477218Z_installed_changes`)
  leaked seven; the original source baseline leaked one. The latest source clean
  exit does not resolve this intermittent issue or exclude a regression. The
  leaked IDs do not match the recorded water snapshot; their owners remain unknown.
  Gameplay triggered-window p99 **21.106 ms**, maximum **26.913 ms**; root GPU
  mean **11.981 ms**, p99 **13.425 ms**, maximum **14.150 ms**. Arrival is
  **26.913 ms**. Normal save stage **7.239 ms**, component capture **7.173 ms**,
  water **0.810 ms**, structures **5.173 ms**; the save frame is **24.580 ms**.
  First-zombie scene setup is **1.274 ms**, but anatomy still **39.050 ms**,
  hit areas **10.367 ms** and ragdoll **5.738 ms**. These timings do not qualify
  stable 60 FPS or remove the earlier observed 91 ms gameplay stall.
- Pack contracts: `reports/performance_changes/pack_contracts_20261109T091454Z`.
  Destruction admission/rejection **25 assertions**, exact debris geometry and
  custom-decoded audio pass. All five selected sounds have identical PCM hashes,
  rates and channels in source and package. Original WAV bytes are unchanged;
  raw import mode and PCK-compatible reads repair the prior export blocker.
- Final export passes building/notice/startup/resource gates, smoke and house
  lighting checks. Building report: `reports/building_standards/20261109T092241325430Z`.
  `dist/TerraForest.pck`: **556,519,008 bytes**, SHA-256
  `bbd8ab699e98383ae14c582cfe3d43354a5c79a19affbda7158464614dca7d6b`.
  All fourteen packaged native DLL hashes match source; the final trace's
  `run.json` records each hash. Root executable is unchanged. Peak sampled private
  commit **3,809,828,864 bytes**, dedicated GPU allocation **1,492,766,720 bytes**,
  within provisional budgets; instantaneous/driver peaks remain unqualified.

Trace percentile figures above cover deduplicated triggered windows, not an
unbiased whole-session distribution. Later short runs cannot establish a causal
improvement in GPU headroom; timing and thermal variation remain possible.

Failed setup checks are not hidden: `083239158841Z` used a graphical vehicle test
headlessly; water checks `085235037841Z`, `085552780291Z`, `085807464514Z` and
`090210469575Z` used legacy startup/headless assumptions, with the latter runs
waiting for a draw signal unavailable headlessly. The graphical water rerun
above supplies the missing integrated verification. `084203781107Z` lacked undo
history in its fixture; the corrected test passes. `085300589491Z` caught the
vehicle tracer assumption, subsequently fixed and retested.

## Required next work and acceptance

Working target: keep both CPU and GPU critical work around **12 ms or less** at
the unchanged 1080p quality, leaving margin inside the **16.67 ms** presentation
budget. A cap reading 60 FPS, a microbenchmark, or a screenshot is insufficient.

| Requirement | Still missing / return trigger | Closing evidence |
| --- | --- | --- |
| Rendering headroom | About 4,900 draw calls and ~15 ms root GPU cost remain; investigate pass costs and native instance/chunk batching before changing quality | Matched idle, walking, turning, driving and dense-settlement CPU/GPU traces; unchanged silhouettes, shadows, coverage and distances |
| Independent later stalls | 78–91 ms frames show 2–5 physics steps and large draw intervals without new pipeline compilation; stage totals do not establish the whole cause | Native/engine CPU stack or presentation trace plus a causal controlled fix; repeat beyond first minute |
| Zombie admission | Preloading addresses resource I/O, not all scene/anatomy/hit-area construction | Bounded/staged admission or reusable immutable anatomy preparation, tested during travel and spawning with pose/hit/ragdoll parity |
| Zombie route latency | Existing cold multi-floor regional graph failure and long recalculation remain; no navigation budget/safety checks were weakened | Fix topology/route reuse with native shared regional work; complete multi-floor and moving-goal pursuit checks under the same collision/readiness budgets |
| Saves at large scale | Water capture improved to 0.81–0.88 ms in these default-world runs; structure snapshots still take 5.17–5.87 ms and whole save frames exceed budget | Normal gameplay autosave traces on edited populated worlds, exact concurrent-edit/reopen equality, bounded memory and worker backlog |
| Destruction under sustained load | Mutation/decomposition fixed; native chunk rebakes, physics insertion and 96 active bodies can still dominate a frame | Repeated real barrel chains and collapse across streamed chunk/water boundaries, bounded frame tails and exact interrupted recovery |
| First missing photograph / new materials | First screenshot readback and unprepared later material variants remain possible stalls | Cold generated-world and first weapon/effect traces; asynchronous readback/preparation if causal, unchanged capture and materials |
| Clean lifecycle | Intermittent anonymous ObjectDB leaks: one in the earlier baseline, seven and three in installed runs; latest source run clean. Regression cannot be excluded | Identify owners and verify repeated source/package world enter/leave plus clean strict exit |
| Multiplayer scale | Revision-checked edits and immutable snapshots are useful foundations, not network simulation | Authoritative command ordering, replication/recovery, native actor scheduling and latency/load tests at a declared population/world size |

Large-scale multiplayer, every-world 60 FPS, old-laptop/thermal endurance and user
visual acceptance remain unqualified. These are explicit continuation requirements,
not completed features. Compute shaders should be selected for a measured suitable
workload; authoritative edits and immutable asset preparation did not require them.

## Reproduction

```text
python tools/check_frame_trace_world.py --short --save --label fresh_changes
python tools/check_frame_trace_world.py --short --save --executable --label installed_changes
python tools/check_water_patch.py
python tools/check_block_cell_patch.py
python tools/run_godot_check.py destruction_batches --headless --timeout 45 --require "DESTRUCTION_BATCHES checks="
python tools/run_godot_check.py debris_geometry --headless --timeout 45 --require "DEBRIS_GEOMETRY failures=0"
```

Changing block shape sources requires `tools/bake_debris_geometry.gd`; export
rebuilds it automatically. `--check-only` verifies source/engine/output identity.
Normal play tracing remains opt-in, with Ctrl+Shift+F12 and automatic low-FPS
windows as documented in [FRAME_TRACE.md](../../docs/FRAME_TRACE.md).

## Implementation commits

- `5031fd07`: native immutable water snapshot storage and debug/release artifacts.
- `5db5aec6`: first-person loading preparation and worker photograph validation.
- `780ce4a4`: optional vehicle preparation and explicit default-zombie dependency.
- `df99e971`: native destructive batches and exact binary debris collision.
- `1bb63e94`: unchanged raw audio packaging and PCK-compatible custom decoding.
- `44adcc40`: gameplay save attribution and reproducible source/installed tracing.
- `c5626dd2`: assert successful normal gameplay save completion in the trace driver.

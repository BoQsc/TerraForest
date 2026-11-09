# Redundant shadow updates and physics boundaries

Status: native guard installed; source/release and packaged checks pass;
stable 60 FPS remains open.
This continues the [terrain partition comparison](terrain-collision-publication-2026-11-09.md)
without changing collision size, geometry, simulation, shadow distances or quality.
New code is original AI-assisted 0BSD maintenance. Engine source was inspected
for attribution; no engine implementation or new dependency was imported.

## Rendering fix

Every `NativeStaticBatch` reselection previously submitted the shadow state of
every retained draw node, including unchanged values. Repeated policy updates
did the same. The node's actual current state is now checked before submission;
real state changes still reach the renderer. There is no extra state cache,
new ownership rule, reduced coverage or change to first-time page publication.

In pinned Godot `ed1daf0bf`, the
[GeometryInstance3D setter](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/scene/3d/visual_instance_3d.cpp)
always forwards the call; the
[renderer setter](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/servers/rendering/renderer_scene_cull.cpp)
queues a geometry update without an equality guard. This explains why otherwise
cheap repeated state submissions can add later rendering work.

Debug/release native builds pass and retain the pinned Dictionary lifetime repair.
Both variants pass 12 shadow-policy assertions, including focus movement across
the shadow boundary and return, repeated policy, and exact placement snapshots.
Both also pass 28 rendered partition checks covering actual GPU data, bounded
residency, movement, partial pages, fades and retirement.
[Build/check receipts](../../reports/performance_changes/20261109T200720936555Z_shadow_guard_checks/result.json).

## Trace boundary correction

The existing `physics_ms` measures scene callbacks through the late recorder,
not the complete physics-server step. A new `physics_tail_ms` measures from the
end of that callback to the next physics/process signal. It includes engine
stepping, queued work, transform updates, synchronization and other work; it is
not isolated Jolt time. Initial preparation before the first physics signal is
still outside both intervals. The pinned
[main loop](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/main/main.cpp)
and [SceneTree](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/scene/main/scene_tree.cpp)
establish these boundaries. Neither field is additive to total frame time.

Catch-up steps retain every closed gap. Drawing/frame limiting cannot extend a
closed gap; each rendered frame resets the accumulators. Thread-cycle/CPU-time
counters preserve unavailable values, and completion/segment counts expose
missing coverage. The analyzer excludes incomplete or old unavailable samples.
No processing priorities, simulation steps or graphics settings changed.
The recorder passes 59 assertions in each native variant; seven analyzer tests
pass. [Debug recorder run](../../reports/checks/20261109T200101584594Z/run.json),
[release recorder](../../reports/performance_changes/20261109T200720936555Z_shadow_guard_checks/frame_trace_release.json).

The first source capture has 3,703 matched ordinary-view frames, 2,644 physics
steps and 2,644 complete tail segments. In its 32.788 ms outdoor frame, callbacks
take 5.645 ms, the tail 0.818 ms and drawing 19.908 ms. Another 30.787 ms frame
contains a 22.030 ms after-process gap with only 286,223 thread cycles, versus
11,784,797 cycles in its 4.936 ms draw. This supports separate CPU-heavy drawing
and low-thread-work waits; it does not identify a wait owner. Earlier script
profiler totals include worker-thread functions and cannot be subtracted from
main-thread wall time as though all functions ran there.

## Source comparisons

The retained generator-29/seed-1703 default world was cloned for every run.
Normal world services, same 16 m fly-camera route, 1920×1080, uncapped rendering,
normal save and shutdown are retained. All four runs use the same new recorder.
The initial old-DLL diagnostic preceded building/checking the guard. The following
candidate/old/candidate sequence provides nearby controls, with recorded DLL hashes
and a process guard before each replacement. The candidate DLL is restored last.

| Continuous phase, milliseconds | Old DLL A2 | Guard B | Guard B2 |
| --- | --- | --- | --- |
| Outdoor median / p99 / max | 15.604 / 24.408 / 31.868 | 13.469 / 22.353 / 28.877 | 12.369 / 21.080 / 23.042 |
| Arrival p99 / max | 21.562 / 26.325 | 18.656 / 29.010 | 19.243 / 38.035 |
| Turning p99 | 23.550 | 18.929 | 17.702 |
| Settled idle p99 / max | 13.512 / 16.679 | 15.242 / 19.088 | 14.181 / 17.064 |

On matched ordinary frames with cover selection over 0.1 ms, drawing median is
**13.890 → 6.449 / 5.311 ms**, and shared render-setup median
**2.042 → 0.413 / 0.394 ms** (14/13/14 frames). These small filtered samples are
not whole-session medians. Together with the engine code path, they support
removing redundant state submissions. Arrival maxima and settled tails do not
establish general nonregression; the remaining waits are not fixed by this guard.
B2 also retains a 38.572 ms ordinary-view trace interval with 33.947 ms drawing
and relatively little thread work. All screenshot intervals are excluded.

No competing engine/compiler was observed in one-second host samples, excluding
the idle Project Manager; this does not prove an idle OS. Whole-run median GPU
clocks were 1260/1147.5/1170 MHz in B/A2/B2, at 52/53/54°C. These are device-wide,
not phase-aligned controls, and differ from earlier high-clock runs. Final cover
indices contain 81,497 records in each run. A2/B2 have 67,823 resident records
and 1,748 draw batches; B has 67,941/1,759. Final shadow-batch counts are
225/213/219 in A2/B/B2. Residency, focus-update timing and live actor positions
vary; these are not identical final draw workloads. The policy and deterministic
boundary tests preserve requested shadow states, not pixel equality of live runs.

All four normal saves/shutdowns pass without error/leak diagnostics. Source peak
memory exceeds the provisional 4 GiB warning in these runs; the hard sampled
limit is not exceeded. This is not leak-endurance acceptance or a memory fix.
[Measurements, identities, images and limits](shadow-updates-2026-11-09.json).

## Installed comparison

The refreshed 626,968,424-byte PCK and all fourteen external native libraries
match the recorded source hashes. Export/startup, 36 packaged house-light checks
and both sequential normal-world save/shutdown runs pass without error/leak
diagnostics. The three updated bake receipts change source identities only;
their baked output hashes are unchanged. This package includes current master,
including the previously committed PX9 reload trial; this report does not add
separate player approval of that trial.

The traced run has 4,457 gameplay frames with current block/model/light profiles,
2,980 physics steps and 2,980 complete tail segments. Joining retained traces to
ordinary observation phases leaves 4,030 frames and 2,644 steps, with no incomplete
tails. Tail p99/max is 1.178/3.341 ms. A 28.386 ms save-phase trace frame contains
14.692 ms in two physics callbacks, 3.341 ms in their subsequent gaps and 6.414 ms
drawing. Another contains 18.171 ms drawing. These need separate attribution;
the native shadow guard does not resolve every callback or drawing stall.

| Continuous phase, median / p99 / max ms | Recorder on | Recorder off |
| --- | --- | --- |
| Arrival | 10.545 / 19.232 / 24.704 | 7.374 / 15.800 / 24.808 |
| Outdoor sweep | 12.882 / 20.223 / 21.421 | 7.665 / 18.258 / 24.696 |
| Turning | 10.666 / 17.871 / 19.162 | 6.967 / 11.132 / 14.576 |
| Settled idle | 9.432 / 13.092 / 14.498 | 7.227 / 11.472 / 12.477 |
| Save during play | 19.838 / 27.722 / 27.722 | 8.619 / 14.865 / 23.730 |

Both installed runs have the same final cover counts and no competing engine or
compiler observed. However, whole-run GPU median clocks/power/temperature change
from 1290 MHz / 20.64 W / 53°C to 2175 MHz / 41.32 W / 61°C. This is not an
isolated recorder-overhead comparison. The recorder's own measured callback
median is 0.310 ms; it excludes induced rendering-query and scheduling effects.
The recorder-off control still exceeds the 16.67 ms frame budget during arrival,
outdoor travel and save. Peak private commit is 4.015/3.917 GiB and sampled
dedicated GPU memory is 1.649/1.648 GiB; neither short run establishes memory
endurance. The on run crosses the provisional 4 GiB RAM warning.
[Installed commands, host controls and tail gate](../../reports/performance_changes/host_shadow_guard_pack_20261109T201642589342Z/result.json).

## Visual review and remaining work

All four captures from the final old/candidate pair were inspected: arrival and
outdoor views 0, 1 and 2. They retain building/road geometry, hillside cover,
trees, boulders, held pickaxe and expected shadows. Wind/camera details differ;
a live zombie has reached the candidate's final arrival view. No obvious visual
regression was observed; continuous seamlessness and world-design acceptance
remain separate. Earlier diagnostic/candidate images are retained but not claimed
reviewed here. Captions and provenance: in-engine 1920×1080 captures of the same
owned default-world source and normal visual settings, generated by the retained
`frame_trace_world` fixture; no image edits or new art.

All eight installed captures (arrival and outdoor 0/1/2, recorder on/off) were
also inspected. Buildings, road, hillside cover, trees, boulders, pickaxe and
their expected shadows remain present, with no obvious visual regression in
these views. This adds static-view evidence, not continuous-motion acceptance.

| Installed recorder on, outdoor start | Installed recorder off, outdoor start |
| --- | --- |
| ![Installed trace, normal cover and shadows](../../reports/performance_changes/20261109T201642758608Z_shadow_guard_pack/outdoor_0.png) | ![Installed control, normal cover and shadows](../../reports/performance_changes/20261109T201818740266Z_shadow_guard_pack_off/outdoor_0.png) |

| Old DLL, outdoor start | Shadow guard, outdoor start |
| --- | --- |
| ![Old DLL, normal world and shadows](../../reports/performance_changes/20261109T200952751741Z_shadow_legacy_a2/outdoor_0.png) | ![Guard, normal world and shadows](../../reports/performance_changes/20261109T201127148676Z_shadow_guard_b2/outdoor_0.png) |

Heavy drawing, low-thread-work waits, surface publication, remaining body callbacks,
cold pursuit, dense explosions/collapse, total recorder overhead, long-session
memory and weaker hardware remain open. Use the new trace to select the next
change; keep normal recorder-off controls. Stable 60 FPS with headroom and future
multiplayer scale are not established by this localized rendering fix.

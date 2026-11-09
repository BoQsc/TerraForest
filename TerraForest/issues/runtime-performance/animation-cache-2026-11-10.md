# Shared animation cache invalidation

Status: source correction verified; stable 60 FPS with headroom remains open.
Original code/test changes are 0BSD. Approved cap, VSync, background cap,
animation clocks, assets, loop modes, density and gameplay rules are unchanged.

## Confirmed cause and correction

`zombie.gd` assigned shared Animation loop modes during every idle/walk selection,
even before its unchanged-playback early return, and during each new admission.
On the installed Godot runtime, these same-value writes emit resource changes
and clear existing AnimationPlayer track caches. The new regression test on old
source observes **60 changes/cache clears for 60 idle selections**, and **12**
more clears when admitting another resident. Equality guards remove both sets
of invalidations. Real loop-mode changes still apply, playback cursors remain
unchanged, and all authored action loop modes remain exact.

Checks: old-source expected failure `reports/checks/20261109T220655257895Z`;
corrected six-assertion regression `20261109T220946006484Z`; 30 geometry/cache/
pose checks `20261109T220947640697Z`; 19 graphical behavior checks
`20261109T221341722935Z`. All corrected checks pass without error/leak diagnostics.

## Normal-policy world comparison

[Machine-readable evidence](animation-cache-2026-11-10.json) records runtime-loaded
source hashes, all phase distributions, resources and retained source reports.
The old/corrected pair uses fresh owned clones of generator 29, seed 1703, at
1920×1080. Every sampled gameplay phase retains cap **60**, VSync **enabled**.
Host sampling observes only one gameplay engine plus the pre-existing idle
project manager. No concurrent native build or other gameplay capture was run.
The hidden-HUD draft is identical in both runs; these numbers do not isolate it.

| One-step physics callback interval | Old median / p99 | Corrected median / p99 |
| --- | --- | --- |
| Arrival | 2.445 / 3.523 ms | 2.125 / 3.295 ms |
| Outdoor camera sweep | 3.153 / 3.957 ms | 2.663 / 3.438 ms |
| Turning | 2.995 / 3.968 ms | 2.057 / 3.129 ms |
| Settled | 2.612 / 3.710 ms | 1.929 / 2.908 ms |

This is a scoped CPU improvement, **not general frame-time nonregression**.
Arrival frame p99 changes 21.937→22.443 ms; outdoor 19.822→20.247 ms. Turning
and settled tails improve, but the candidate has a **49.358 ms** recovery frame:
39.013 ms drawing, only 9.82 million main-thread cycles in that interval,
2.751 ms viewport CPU and 6.076 ms reported GPU. GPU measurements can lag.
This was 2.434 seconds after the chain, before normal eight-second debris
retirement; the trace writer was inactive. Its exact wait owner is unresolved.
Do not blame it on actor work or claim the guard fixes rendering waits.

Both runs preserve the real three-barrel damage oracle, 96 physical debris,
normal retirement, save and clean shutdown. A further capped walking run
`20261109T221529566537Z_animation_guard_walk_capped` moves **16.868 m** using
the production player motor and collisions; **184/184** movement samples are
grounded. It uses the existing tool-cursor input gate to avoid capturing the
desktop pointer. This improves on the earlier fly-camera-only coverage but is
not a full manual playtest. Walking p99/max remains 23.879/24.363 ms; recovery
max is 29.961 ms. Memory reaches the provisional 4.03 GiB warning band; this
is not long-session leak qualification.

## Inspected views and limits

The following retained project screenshots were inspected. The outdoor pair
retains terrain, grass, trees, buildings and held-tool presentation; moving wind
is not pixel-identical. Destruction retains physical rubble. The behavior view
shows the normal chasing pose; geometry tests independently check skinned poses.
These are scoped engineering observations, not universal visual acceptance.

- [Old outdoor view](images/animation-guard-outdoor-old.png)
- [Corrected outdoor view](images/animation-guard-outdoor-new.png)
- [Corrected destruction](images/animation-guard-destruction.png)
- [Chasing behavior fixture](images/animation-guard-chase.png)

The earlier `20261109T220731960843Z_animation_baseline_capped` is excluded from
the comparison: source changed after launch, before runtime source hashing was
added. The paired runs above keep selected source unchanged for the whole run
and validate loaded script hashes. Their driver/source snapshots/host telemetry
remain in `reports/performance_changes/host_animation_guard_20261109T220949524605Z`.

## Remaining gate

Rendering waits, live admission peaks, broader traversal, terrain edit latency,
endurance and installed-package verification remain required. Windows WPR CPU
profiling fails with `0xc5585011` (profiling policy unavailable); no system policy
was changed and no stack-level diagnosis is claimed. Continue reducing actual
work with the [approved pacing policy](approved-pacing-2026-11-10.md) intact.

# Canopy snapshot stalls

Status: cause confirmed, native correction is installed and passes functional,
controlled world and packaged gameplay checks. Stable 60 FPS with
headroom remains open. Original AI-assisted code is 0BSD; no new dependencies.

## Confirmed cause

The canopy rasterizer already runs on a worker, but preparing each immutable job
walks every tree's script dictionary on the main thread. The quarter-second
rebuild gate produces periodic process spikes while trees are arriving; crossing
a 16 m mask origin also triggers preparation during walking.

`reports/performance_changes/20261109T223840917491Z_canopy_snapshot_attribution`
passes foreground 1920×1080 fullscreen, render scale 1, cap 60, background cap 15
and VSync enabled. Production motor walking covers 88.372 m with 964/964 samples
grounded. Destruction, HUD, save and shutdown pass without error/leak diagnostics.
Retained current canopy samples in arrival/walking reach **5.333 ms** preparation
for 8,586 trees, inside a 9.493 ms process / 24.995 ms frame. These are triggered
trace windows, not a complete-session snapshot distribution.

## Correction

Accepted forest upserts/removals maintain native transforms and an ID-to-slot
index. Snapshot preparation copies contiguous transforms into a private worker
job instead of rebuilding them through thousands of Variant dictionary lookups.
Swap removal updates the moved ID's slot; LOD certificate resets retain canopy
membership. Worker inputs remain immutable during later edits or owner removal.

The shadow rasterizer, masks, tree assets, sun rules, 256-pixel maximum, 65,536-root
snapshot bound, update cadence and stale-publication rejection are unchanged.
Foreground/background caps and VSync are unchanged. The retained dictionary path
is an explicit diagnostic control, not the normal runtime path.

The 42-assertion snapshot regression verifies exact mask bytes against that old
path, including removal/replacement, unchanged updates, origin shifts, concurrent
source edits and limits. At 16,384 roots, debug preparation median is
10,658 µs dictionary / 114 µs native in the isolated fixture. This is preparation
cost, not a whole-frame FPS result. Original canopy and scripted/native forest
state/slot/transform/boundary checks also pass in debug and release.

- Debug snapshot: `reports/checks/20261109T224335544784Z`.
- Debug original canopy: `reports/checks/20261109T224406323996Z`.
- Debug forest parity: `reports/checks/20261109T224418585990Z`.
- Release suites: `reports/checks/canopy_release_20261109T224500387302Z`.

## Foreground world comparison

[Machine-readable evidence](canopy-snapshot-2026-11-10.json) retains exact source
and native hashes, presentation, phase distributions, resource checks and the
worst retained frames. The old-path control deliberately uses the same new DLL
and maintains the same native membership index; only snapshot preparation differs.
Both captures use generator 29/seed 1703, 1920×1080 foreground fullscreen, cap 60,
background cap 15 and VSync enabled. One-second process sampling observes at most
one game and no compiler besides the pre-existing idle project manager. This
does not establish an otherwise idle OS or identical thermal conditions.

| Measurement | Dictionary control | Native snapshot |
| --- | ---: | ---: |
| Retained walking snapshot median / max | 4.872 / 5.081 ms | 0.074 / 0.147 ms |
| Arrival frame p99 / max | 21.397 / 30.208 ms | 19.583 / 20.653 ms |
| Walking frame p99 / max | 20.846 / 25.377 ms | 20.717 / 22.989 ms |
| Destruction chain frame max | 21.865 ms | 22.327 ms |
| Recovery frame p99 / max | 18.604 / 46.343 ms | 19.207 / 20.533 ms |

Six current snapshots are retained per walking run. Snapshot preparation drops
about 98.5%; the frame tails are mixed and remain above 16.67 ms. Absence of the
control's 46 ms rendering-heavy recovery frame in the candidate does not prove
that rare wait is fixed. Both walks cover about 88 m, with all 964 movement samples
grounded, and retain damage, 96 physical debris, normal retirement, HUD, save and
clean shutdown. Both peak private-commit samples enter the provisional 4.01 GiB
warning band; no long-session memory acceptance is claimed.

Reports: `20261109T224505451708Z_canopy_dictionary_control` and
`20261109T224656084274Z_canopy_native_snapshot`, with host telemetry in
`host_canopy_snapshot_20261109T224505277433Z`, under `reports/performance_changes/`.

The matching start views and native endpoint below were inspected: terrain,
grass, trees, boulders, buildings and held-tool presentation remain present.
Moving wind is not pixel-identical; exact canopy mask equality is established by
the native fixture. Existing HUD overlap/held-pickaxe presentation is unchanged
in both views. These observations are scoped engineering checks, not universal
visual approval. Images are project captures; existing asset provenance applies.

- [Dictionary-path outdoor start](images/canopy-dictionary-start.png)
- [Native-snapshot outdoor start](images/canopy-native-start.png)
- [Native-snapshot walking endpoint](images/canopy-native-end.png)

## Installed verification

The export passes building standards, smoke and packaged house-light checks with
14 matching external native libraries. PCK SHA-256:
`5f4b51c2b142830a32820fbc091d5b2c696714b3f10e56030317e16f969066ed`.
All 42 snapshot assertions pass against this actual package in
`reports/checks/canopy_pack_20261109T225521Z`.

The export initially stopped at the existing disk reserve. No reserve was
relaxed and no saves/evidence/history were removed. NTFS compression of the
rebuildable Zig cache retained all 1,543 files with identical SHA-256 hashes;
`reports/performance_changes/canopy_export_cache_compression.json` records it.

Both installed foreground fullscreen runs cover 88.372 m with 964/964 movement
samples grounded; destruction, HUD, save and shutdown pass without error/leak
diagnostics. Every measured gameplay sample retains cap 60 and VSync enabled;
background cap stays 15. The off run disables the recorder and per-frame GPU
timer queries. Neither is FPS acceptance:

| Installed run | Walking p99 / max | Recovery p99 / max | Settled max |
| --- | ---: | ---: | ---: |
| Recorder off | 20.246 / 21.960 ms | 19.251 / 43.452 ms | 20.098 ms |
| Recorder on | 20.719 / 21.880 ms | 19.123 / 23.089 ms | 42.608 ms |

Reports are `20261109T225524992678Z_canopy_installed_normal_off` and
`20261109T225837786630Z_canopy_installed_normal_trace`. Current walking snapshots
in the installed trace have median/max **0.061/0.146 ms**. Compiled scripts do
not expose source text in this export: the earlier empty-text hashes are not
script identity. The harness now records unavailable source explicitly; package
and native hashes identify the installed build. The normal-policy harness also
now fails cap/VSync mismatches, not just uncapped-control mismatches.

The 42.608 ms settled frame spends **31.262 ms drawing**, with 11.42 million
draw cycles, 1.687 ms physics callbacks and 1.242 ms process. Adjacent ordinary
draw intervals use about 9.5–11.1 million cycles in 4–5 ms. Canopy preparation
and the trace writer are inactive; pipeline counters do not increase. Viewport
CPU timing reports 29.642 ms two callbacks later. This is a remaining renderer
work/wait boundary, not a canopy or zombie diagnosis. Completion timestamps must
be correlated before assigning its exact owner. Another chain frame spends
9.221 ms processing, including 4.444 ms terrain staging and 2.538 ms LOD work.

## Rejected checks and open gates

The first fullscreen harness run (`20261109T223526518816Z_normal_window_long_walk`)
completed walking/destruction and saved, but its new final assertion read the
game object after freeing it. It is a failed verification, not a clean shutdown
pass. The diagnostic process was closed after saving; the assertion now reads
its retained observation and the subsequent attribution run passes. The first
forest parity launcher (`20261109T224407312745Z`) requested a marker the existing
test does not print; it is retained as failed and repeated with its actual marker.

Next: correlate delayed renderer markers with the long draw interval; reduce
remaining terrain publication/LOD work while retaining atomic visual/collision
publication. Revisit broader pursuit/traversal and multi-world memory endurance
after these frame owners are bounded. Closure requires repeated foreground
normal-policy gameplay with frame-time headroom, unchanged visuals/damage and
collision checks, and stable resident resources across return/reopen cycles.
No universal visual approval or stable-FPS result is claimed here.

## Renderer marker follow-up after storage audit

The blocked attempt was repeated after the [storage audit](storage-audit-2026-11-10.md)
and maintenance, using the same installed package. Report:
`reports/performance_changes/20261110T060109542024Z_canopy_remaining_render_markers`;
host inventory/GPU clocks:
`host_remaining_render_markers_20261110T060108244562Z` in the same parent folder.
The host inventory observes only the owned gameplay PID 29980 plus the pre-existing
idle project manager. Fullscreen 1080p, render scale 1, cap 60, VSync 1 and background
cap 15 are preserved; all measured gameplay is focused. Walking covers 88.188 m,
943/943 movement samples grounded. Destruction, normal save and shutdown checks
pass without error/leak diagnostics. Private commit peaks at 4.01 GiB (warning).
The start/end images `outdoor_0.png` and `outdoor_2.png` were inspected: terrain,
grass, trees, boulders, buildings and held tool remain present, with the earlier
HUD/held-tool issues unchanged. This is scoped observation, not visual approval.

Completed CPU markers are matched by absolute timestamps to their draw intervals.
Frame 4598 is 29.815 ms, including 19.341 ms drawing but only 11.61 million draw
cycles (nearby normal draws use 9.9–10.3 million). Its **14.670 ms** gap runs from
`Update Occlusion Buffer` to `Update Visibility Dependencies`; it is reported in
frame 4599. Viewport CPU time reports 17.635 ms in frame 4600, confirming why a
current-callback GPU/CPU timer cannot assign the stall. The nearby occluder state
is unchanged: four active, 4,032 geometry bytes, no uploads or pending work.
Canopy preparation is not current and its worker is idle. No PSO cache update is
logged after the 31.7 MiB startup cache, so this capture supplies no support for
pipeline-cache serialization as this stall's cause.

The marker name does not isolate occlusion itself. The
[pinned engine source](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_scene_cull.cpp)
places occlusion-buffer update, initial scene/light setup and the SDFGI update
boundary between those markers. Worker waiting, preemption and the exact blocking
call remain unresolved. Do not disable occlusion or alter its approved bounds
based on the marker label alone.

This run enables `--gpu-profile` and `--verbose`; it is diagnostic, not a normal
FPS comparison. It also records 53–207 ms outdoor delays primarily before process,
with catch-up physics, and larger screenshot intervals. Those observations are
retained in `observation.json`, `summary.json` and `attribution.json`; they are not
silently removed, assigned to game code, or declared fixed. Profiling/logging
perturbation and system scheduling must be isolated. Next evidence: quieter
render markers or engine-level wait attribution, followed by normal-policy
recorder-off confirmation before adopting any production change.

## Foreground walking attribution — 2026-11-10

The installed-package quiet-marker capture `reports/performance_changes/20261110T083559880386Z_canopy_quiet_render_markers` passed foreground, walking, destruction, save and shutdown checks with the approved cap and VSync. Outdoor walking reached 28.943 ms; its 28.917 ms recorded frame includes 14.390 ms before process, 5.729 ms in process and 8.694 ms draw. Physics callbacks occupy 6.295 ms of the first interval; terrain surface-result delivery takes 1.157 ms and mesh creation/upload 0.663 ms in that frame. These stages overlap their parent intervals and do not independently explain the full frame. Another walking frame reaches 25.862 ms with 12.818 ms drawing and 1.318 ms terrain scheduling. The earlier 14.670 ms occlusion-marker gap did not recur. The exact causes of the remaining unaccounted time are open; 60 FPS with headroom is not achieved.

Two subsequent recorder-on controls lost OS focus and are rejected as foreground comparisons. The second correctly applied the existing 15 FPS background cap, so its incomplete walking/destruction checks are not a gameplay regression result. The uncommitted diagnostic changes acquire/check real focus and retain the background limit; they still need an uninterrupted foreground validation. Next isolate synchronous surface-result listeners and the unaccounted physics/process/draw intervals, then verify any change against matched foreground gameplay and recorder-off controls. Keep failed captures and approved limits intact.

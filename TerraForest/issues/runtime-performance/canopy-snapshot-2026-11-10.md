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

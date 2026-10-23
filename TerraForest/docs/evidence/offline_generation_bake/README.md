# Native offline generation bake

2026-10-23. This closes frame-paced generated-lake authoring and the related map
handoff defects; it does not close the entire world rewrite or qualify runtime
performance, world design, mining latency or laptop thermals.

NativeGeneratedLakeBake owns a detached store on the existing terrain worker. It
uses the same begin_fill, advance, NativeWaterTerrainPatch and accept_patch rules.
There is no new water representation, mesher, fluid simulation or bucket rule.
Only a complete immutable snapshot crosses to normal scene loading. The path is
configured before startup, refuses existing worlds, and is absent in ordinary
playback. GDScript coordinates it; the volume/contact work is C++.

The job is one-shot, checks terrain revision/epoch and cancellation, has a 30-second
default deadline (maximum 60), retains existing region admission, rejects estimated
native state above 128 MiB and output above 64 MiB. The state estimate includes
region/contact storage plus conservative frontier overhead, not process RSS or a
global engine-memory cap. Backend stop cancels before joining its worker. Failure
returns no partial snapshot and does not edit the terrain or canonical save.

## Evidence

- 114725684096Z and 120543733844Z: exact prior generated water bytes, read-only
  terrain, exact runtime restore/catalog cursor, rejected reuse/stale revision/
  malformed input, deadline rejection and in-flight cancellation. Scoped native
  bake observations: 0.99 s and 0.87 s for 872 regions / 13,187,368 snapshot bytes.
  Cancellation returned in about 0.6–1.1 ms in these observations. No universal
  latency bound is inferred from those samples.
- 115014433104Z: production backend startup with four inland lakes, 1,626 regions,
  31,053,016 snapshot bytes, about 2.21 s; completed occupancy before publication,
  immutable configuration, existing-world protection and stop cancellation pass.
- Source coastal 1703: actual creation 41.9 s, native lake job 1.05 s; subsequent
  fresh full-game reopen 11.1 s with all four map layers hitting cache.
- Final source inland 42: actual creation 28.5 s; fresh full-game reopen 19.0 s,
  all four map layers hit cache with zero terrain patch rebuilding. Earlier full
  source creation took 34.1 s with a 2.04-second lake job.
- Explicit PCK coastal creation: 59.9 s, native lake job 1.08 s, one generation
  child and native binary verification. First photographs/residency took 36.0 s.
  Full packed playback plus three location photographs took 17.8 s and left the
  canonical root SHA unchanged. This is the current editor executable plus PCK,
  not a clean-machine release-template qualification.
- The terrain, structures, generated_region and volumetric_water section hashes
  match the retained prior-generation baselines for both seeds/layouts. The
  equivalence JSON records each comparison; player pose/presentation are separate.
- Block map content/cursor separation: 115558734336Z. Real content changes and
  resident-region replacement invalidate; exact paging/no-op edits preserve the
  content stamp. Paging still invalidates region cursors. Block survey and model
  identity checks pass 115558720222Z / 115558721042Z.
- Water serialization preserves logical revision/certification: 120543733989Z.
  Coordinator cancellation still passes 120055023746Z.

These are fixed-scope warm/cold observations on the current hardware, not controlled
whole-generator speedup estimates. The previous frame-paced lake stage took 15–29 s;
first photographs and finalization/handoff remain substantial after its replacement.

## Failures retained and resolved

- 114744076996Z / 114918916261Z: generation reached the save/map stage but rejected
  the saved block stamp. Exact residency transfers advanced the fallback counter
  even with no authored changes. A native logical content counter now separates
  those changes from residency-sensitive cursors; the guard remains enabled.
- 120001230106Z: inland playback worked but water rebuilt its map layer. Snapshot
  serialization itself cleared its certificate/advanced its map revision. Capture
  now changes only derived serialization caches. An alias binds generation's
  raster to the exact saved snapshot identity, as with the building layers.
- 120546647494Z: the first water alias call incorrectly specified the building
  raster's 512 size for a 256 raster. The native cache rejected it, publication
  stopped, and the call now uses each layer's actual size/normal quota.
- The initially failed staging roots remain diagnostic; none was published as a
  ready world. Successful source and PCK runs occur after these corrections.

Reopened world/map images were inspected. Their data/UI continuity is accepted for
this check; the repeated building family and landscape shortcomings remain rejected
world quality. The inland map capture shows a 36 FPS HUD during initial capture;
this harness does not establish steady runtime frame cost or thermal headroom.

Still required: cheaper first-image/residency and finalization/handoff; selective
terrain paging beyond the resident/history cap with exact distant edits; retained
checkpoint GC/compaction; the failed rendered mining-arrival gate; pending lake
shutdown/ID-cursor persistence; remaining options/map/POI/compute/vegetation cases;
world design acceptance; populated 1080p/60 FPS and thermal proof. No feature has
been silently moved to post-release.

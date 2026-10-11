# Rejected grass texture v2 experiment, 2026-10-11

**Human review: rejected as cartoonish and unrealistic.** This version is archived
here, not used by the live grass material. The untextured preferred shape remains
the default; F7 still offers the previous v1 trial. Numeric validation below is
not visual approval. The stronger parallel bands read as painted stripes on the
folded blades. Avoid further contrast increases as a substitute for realism.

The exact rejected shader, factory and static test are retained under `experiment/`.
The static test can be run manually with Godot --script pointing to that file.


Human feedback: v1 mostly dimmed grass instead of adding visible leaf detail.
New built-in image_gen output has a clear central vein, parallel vein bands,
longitudinal colour streaks and sparse upper-edge weathering. Original output is
retained as `experiment/grass_detail_v2.trtex` (PNG bytes), with
exact prompt/provenance in `experiment/grass_detail_v2.prompt.json`. V1 assets remain available.

Replaced guessed RGB normalization and narrow clamping with measured linear RGB
mean. A1024-sample calibration runs once when the shared256x256 mipmapped texture
is first loaded; it never runs per instance or per frame. Shader still uses one
texture read; blend strength0.65. Same geometry, texture size, instance counts,
opaque material and LODs. The experimental toggle was optional and default off during testing.

Validation:7 static close-up checks and44 asset/interaction checks pass; world
support and off/on/off comparison pass. Static rendered foreground mean linear
brightness ratio0.9933 (only0.7% lower); average absolute pixel change9.65% relative
to baseline brightness. This measures visible variation without a uniform dimming.
Off/on/off restores exact original static pixels. Close-up is fullscreen1920x1080;
world uses unchanged player-height views, fullscreen1920x1080, cap60.

World GPU p95 off/on/off:6.169/6.386/6.459ms; medians6.058/6.096/6.027ms.
No clear material GPU regression established by this short sample; not zero-cost
proof. Whole-frame p9518.665ms still fails18.5ms gate. No thermal/endurance claim.
Detail is most visible close up and deliberately fades through mipmaps farther
away. User rejected this material; broader vegetation/terrain integration remains open.

# Playable finite water and bucket persistence

2026-10-11. The actual `demo/world.tscn` is run at fullscreen 1920×1080/cap60
with gameplay enabled, in a unique real save slot. No user save is overwritten.
The checked native builds and logs are retained here.

The integration check covers the normal left-click gameplay handler; exact one-litre
water/bucket conservation; ten-litre capacity; empty/full/stale-revision rejection;
chest deposit/withdrawal; batched dropped filled buckets and recollection; ordinary
compound world saving; disposing the entire world and reopening from disk; native
surface publication; and guarded edits near established water. The screenshot was
inspected in the actual forest/terrain scene. The water and held/belt bucket are
visible. The lake remains a simple authored basin; this is not final water art.

`generated_finite.log` covers all four generated lakes for seed1703 after selecting
seed-connected air and reducing redundant boundary-face anchors. This catches the
failure mode where unrelated exterior air wrongly made a bounded lake appear open.
Other seeds and maximum-size finite bodies are not qualified by that check.

The existing 277-check native network suite passes in debug and clean release;
its topology, quantity, remapping and surface contracts retain their default strict
publication behavior. Main-world rendering opts into retaining a previous surface
while small bucket quantity changes are meshed. This permits visual latency, not
water duplication; inventory and water quantities commit synchronously.

These are functional checks, not sustained 60FPS/thermal/performance qualification.
See [play instructions and explicit limitations](../../WATER_GAMEPLAY.md).

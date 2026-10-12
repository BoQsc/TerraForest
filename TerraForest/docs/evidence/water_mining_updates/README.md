# Mining and water updates — 2026-10-12

One existing regional water implementation; no alternative runtime added.

The actual-world outlet test failed before the change with mining admission held for 10 seconds. The controller and its physics callback are paused only to keep that input state stable; terrain worker, terrain publication, native water and scene rendering continue. An assertion verifies the held state remained set.

Changes: held mining no longer blocks bounded water terrain sampling between edits. Pending terrain edits no longer pause all water processing; native invalid regions still refuse flow. Mesh publication defers regions whose reconstruction neighbourhood has invalid occupancy instead of treating unknown terrain as empty. Eight queue candidates at most are considered per call, preserving fairness and retained dirty entries.

After: 46 actual-world assertions pass, including three consecutive adjacent excavation edits, continued held-brush flow, exact quantities, buckets and cached save/reload. Release native continuity check passes 14 assertions, including deferred publication across invalid neighbours. Debug and release DLLs rebuilt with the pinned prebuilt SDK.

Latest outlet response: 2164 ms from edit submission to wet outlet. Frame median 16.665 ms, p95 16.967 ms, max 46.754 ms, 827 measured frames. Screenshot readback is excluded from frame timing. This is a short regression check, not sustained performance qualification. Maximum native mesh time 1.388 ms still exceeds the 1 ms presentation target.

## Remaining defect — not accepted as visually complete

Inspect water_repeated_mining.png against water_repeated_mining_terrain_only.png. Stepped/slatted moving water remains along the excavated bank. These captures prove water contributes the edges; they do not establish the exact cause of every artifact in the user's screenshot. The first diagnostic camera was misplaced and its capture was discarded; the retained pair explicitly restores the player's normal camera offset.

The tests establish volume transfer, not smooth motion or instantaneous response. Terrain resampling latency and moving-surface reconstruction remain open. No claim of full water completion.

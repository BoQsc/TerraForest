# Ground-cover render selection

Status: native optimization verified and installed; whole-game validation and
stable 60 FPS with headroom remain open.
Original implementation/test changes are AI-assisted project work under 0BSD;
no third-party code or assets were imported.

The valid foreground capture
`reports/performance_changes/20261110T083559880386Z_canopy_quiet_render_markers`
contains a 27.054 ms walking frame (3344). Its nine ground-cover batches spend
3.287 ms selecting pages and 4.024 ms in their complete render callbacks.
The block/model/light callbacks total only 0.173 ms. The GPU measurement is
6.219 ms and may lag. This identifies one CPU contributor, not the entire stall.
Other walking frames still contain expensive draw and physics intervals.

`NativeStaticBatch::select_render_batches` now traverses existing page layouts
directly, eliminating allocated page-key copies and repeated size lookups.
It collects pending uploads during that same traversal. Nearest-first ordering,
byte/draw/upload limits, visible partial pages, eviction and shadow policy remain
unchanged. No quality, density, range, frame cap or VSync setting changed.

The bounded `tests/render_selection_cost.gd` fixture holds 16,384 placements and
2,048 pages, moves selection focus, verifies immutable placement bytes and
resident/budget counts, and prints its timing into the shared runner's receipt.
It creates no world, asset or build copy. Headless timing is a component check,
not a whole-game or GPU performance claim.

Initial debug comparison:

| Build | Median selection | p99 | Evidence |
| --- | --- | --- | --- |
| Previous DLL | 772 us | 2864 us | `reports/checks/20261110T090252934638Z` |
| Direct traversal | 478 us | 1864 us | `reports/checks/20261110T090346981296Z` |

The median improvement is approximately 38%; whole-game improvement remains
unverified. Earlier fixture attempts `090038691763` (headless draw-signal timeout)
and `090201437859` (sampled clean callbacks) are rejected timing evidence.
The fixture now rejects a zero median.

Debug GPU partition regression: 28 checks pass in
`reports/checks/20261110T090412494628Z`, including exact transforms/fade payloads,
shadow policy, movement/removal, partial-page retention, retirement and budgets.
The GPU static-placement run `090449549259` passes 242 data checks but fails its
exclusive-fullscreen assertion; retain it as failed, not universal acceptance.
The headless static-placement run `090530945087` passes.

Release static-placement and GPU partition checks pass with zero failures:
`reports/static_placements_release.json` and `reports/render_partitions_release.json`.
Both debug/release DLLs are installed, all 14 source/distribution DLL pairs match,
and the existing PCK is byte-identical (`reports/render_selection_install.json`).
No new package, worktree or world recipe was created for the native change.

The normal-world attempt
`reports/performance_changes/20261110T090620640293Z_direct_render_selection`
is rejected: 1,519 gameplay frames lost OS focus. The approved background cap
and inactive gameplay behavior applied; walking/destruction checks consequently
did not complete successfully. Manual and shutdown saves completed. The inspected
`outdoor_0.png` retains terrain, ground cover, buildings, trees and the held tool;
this is limited visual evidence, not whole-game acceptance. Peak private commit
was 4.02 GiB (warning), with no leak diagnostic; endurance/leak closure is not proven.
The launcher archived an obsolete owned test world after exit.

Quiet renderer-marker captures now require a matching successful completion
receipt, and normal-window tests follow the production focus/cap policy and
reject lost focus. The earlier valid quiet baseline above passed; later
`084113618751`, `084728067330` and this changed-build run are rejected controls,
not performance comparisons. These harness changes are not runtime FPS fixes.

The subsequent installed capture `20261110T094742623629Z_world_player_headroom`
passes with zero lost-focus samples, grounded walking, barrel destruction and
saves. This closes the missing functional gameplay check. Walking p99 remains
21.028 ms and maximum 37.807 ms; there is no claim of stable FPS or an isolated
whole-game gain. [Current world/player investigation](world-player-headroom-2026-11-10.md)
tracks the remaining renderer wait and collision-preparation costs.

# Create world progress and automatic preview

2026-10-26. Generation launched from the selector remains in the Create world
tab through generation, verification and publication. The embedded loading panel
uses a 6 px bar, the existing stage weights and work counts, elapsed/remaining
time, and cancellation. Recipe controls are disabled while preparing. The normal
loading screen takes over at the published-world handoff and retains its 18 px
bar, elapsed-time carry and playable-readiness gate.

Opening Create world and changing recipe settings schedule a preview after
350 ms. Only one preview worker runs at a time. A superseded result is discarded
and the latest recipe runs next. Refresh preview remains available for retries.
Generation waits asynchronously for an already-running preview so the plan-cache
writers do not race; preview success is not required to generate a world.

All checks below passed under Godot 4.7.2 Forward+ with no reported script errors.
Run using `python tools/run_godot_check.py <test> --godot <engine> --timeout <seconds>
--require '<TOKEN> failures=0'`. Check IDs identify retained local directories in
`reports/checks/`.

| Test | Check ID | Coverage |
| --- | --- | --- |
| `world_browser_progress` | `20261026T062546290929Z` | Controlled coordinator states, actual stage/work display, 6 px bar and cancellation bounds at 1920x1080 and 1280x720. |
| `world_browser_cancel` | `20261026T062618976472Z` | Actual generation stays in Create world; cancellation returns controls and publishes no world. |
| `loading_progress_ui` | `20261026T062656572551Z` | Existing regular loading presentation, timers, diagnostics and playable-readiness gates. |
| `world_browser_generation` | `20261026T062847619383Z` | Actual seed-50 creation, verification, publication and playable load; waits for preview, stays in Create world, preserves timing and then uses normal loading. Also rejects an injected failed publication. |
| `world_creation_ui` | `20261026T062932265821Z` | Automatic preview, debounce, edits during active work, latest-recipe identity and layout at both resolutions. |

Inspected images: [actual generation](generating_1920x1080.png),
[controlled progress at 720p](progress_1280x720.png), and
[automatic native preview at 720p](automatic_preview_1280x720.png).
These checks cover the selector workflow and UI layout; they do not change or
accept generated settlement design, terrain fit or the broader world backlog.

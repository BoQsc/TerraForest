# World-building work

## Commit preference

User direction, 2026-10-25: commit completed, verified work by default rather
than waiting for another commit request. Keep commits focused, include matching
Godot UIDs, and document remaining work without claiming it is complete. Do not
include unrelated user changes. A later explicit no-commit instruction overrides
this preference. Committing does not authorize pushing; push only when requested.

## Godot identity files

Commit Godot `.uid` sidecars with their corresponding source files. They are
versioned resource identities, not disposable import cache. Let Godot generate
them for new resources, then include them when staging the source; check for
sidecars created by a later import before completing a commit.

This repository provides `.githooks/pre-commit` at the Git root to stage matching
UIDs automatically. Enable it per checkout with
`git config --local core.hooksPath .githooks` when no existing hook configuration
would be replaced. Do not add unrelated source changes or cache/report output
while collecting UID sidecars.

## Unfinished-work tracking

Never silently abandon unfinished work or report partial verification as completion.
Before switching milestones, record any remaining requirement in
`docs/WORLD_FOUNDATION_STATUS.md` (or link its dedicated contract from there).
Record what is missing, why it is deferred, its prerequisite or return trigger,
and the evidence required to close it. Keep failed and unreviewed checks visible.
When a prerequisite is completed, revisit dependent work; update the existing entry
instead of letting a newer progress note imply the old requirement is resolved.
Deferral is not completion. Do not expand excluded features to clear a backlog.

For world generation, settlement, road, POI or landscape changes, read
`docs/WORLD_BUILDING_STANDARD.md` before choosing the implementation.

For entity navigation, traversal, pursuit or world-interaction changes, read
`docs/NAVIGATION_STANDARD.md` before choosing the implementation. Reuse the native
route core, declare movement capabilities and interaction permissions, keep one
body-integration owner, and retain explicit blocked/unavailable states and budgets.
Local steering and repeated local horizons do not qualify whole-world navigation.

Keep engineering verification separate from world-quality acceptance. Passing
generation, persistence, movement or performance checks does not override visible
design defects. Inspect relevant generated images before reporting visual success.
Report rejected and unreviewed requirements plainly; do not silently lower the
standard to match the current implementation.

The current northern single-pad district is a development draft, rejected for
terrain fit and visual variety. Prioritize a terrain-fitting block/lot layout over
decorating that rejected layout. Existing user saves must remain intact.

These rules do not prohibit development builds for diagnosis or require additional
user permission. Use short targeted checks, followed by integrated evidence where
the change affects the actual world. Preserve 0BSD and native runtime hot paths.

# World-building work

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

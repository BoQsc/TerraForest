# Regional navigation evidence — active checkpoint

This is unfinished implementation evidence. Component graph, residency, slope and
player regression checks pass; real saved-world tower/cave traversal is still being
rechecked after correcting physical stair contact and profile mismatches. Do not
count interrupted diagnosis runs as successful journeys.

`failed_live_world/` retains assertions and interrupted diagnostic runs. Exit code
4294967295 indicates an owned diagnostic process stopped after its stall was
reproduced, so corrected native libraries could be built. Every retained saved-world
manifest checks the source archive remained unchanged. Older runs do not have
native hashes and cannot qualify final binary identities. `before_adaptive_graph/`
retains the first graph failures; `height_guidance/` is an intermediate component
pass before the final profile, budget and movement changes.

The expanded slow-stair fixture originally missed block collision layer 2; that
fixture error is retained and corrected. Early diagnostic logging also called
get_normal on an empty collision result; that diagnostic error is retained. Neither is a successful gate. The straight entrance driver initially continued
into a perpendicular interior stair wall; it now ends on the entrance landing.
Full upstairs circulation remains the independent autonomous saved-world gate. Final runs will be listed separately with their actual scope.

Implementation and limits: [regional contract](../../REGIONAL_NAVIGATION.md).

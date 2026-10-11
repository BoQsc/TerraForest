# Private settlement and atomic water handoff

2026-10-11. NativeWaterRemapPlan now supports begin_settlement,
advance_settlement(work_budget) and commit. Source quantity remains authoritative
through planning and staging. Replacement profiles are copied one hierarchy node
per unit, followed by one finite-settling event per unit. Profile rows contain at
most 256 anchors; metadata copies and vector reservation are bounded but not fully
incremental. The same work cap and soft 2 ms checks apply. Staged water is private
and cannot be used through the destination network before commit.

Successful commit verifies both mutation counters and destination ownership again,
requires every canonical millilitre to have settled with no unresolved displacement
or overflow, publishes the staged solver, and retires the original network. The
serialized commit has no callbacks or intervening yield. Retired networks reject
queries and mutations and report owned_ml=0. Previously allocated solver data is
retained privately by the transaction to avoid bulk frees during publication; its
later destruction still needs runtime retirement scheduling. Atomic here means a
serialized in-memory ownership transition, not crash-safe disk persistence or
cross-thread synchronization.

203 debug and clean-release network checks pass. Covered cases include complete
staging with a one-operation budget, no publication before commit, exact quantity
handoff, replay rejection, two fully prepared plans competing for the same source,
retired-source writes, source mutation, destination generation invalidation, and
zero work after completion. Added terrain space lowers the settled water level.
An insufficient-capacity profile produces explicit solver overflow even when the
geometric plan has no displacement; commit refuses it and leaves the source intact.
Raised solid terrain likewise cannot commit while displacement remains unresolved.

The actual TerrainCore test excavates a radius-4 cavity crossing two owned regions,
fills it, removes one litre, excavates at radius 5, republishes both density snapshots,
plans and privately settles the replacement, then commits. Replacement owns exactly
129,856,198 ml, old ownership is zero, the level falls, and the spatial query reports
water in the enlarged cavity. This is actual native geometry and quantity movement,
but remains headless and in-memory.

## Remaining work

Displaced water and overflow have accounting and rejection, not physical routing.
They must gain valid destinations before the current handoff may commit. The source
remains intact meanwhile; these checks do not establish live solid placement support.
Busy old pours must be serialized or resolved with their item transactions before
remapping. World scheduling, saved-world transactions, bucket gameplay, rendering,
unloaded-region summaries, adaptive profile accuracy, dirty-region locality, bounded
retirement and sustained 60 FPS/thermal acceptance remain open. Current playable
lakes have not been switched to this finite-water pipeline. Original code is 0BSD.

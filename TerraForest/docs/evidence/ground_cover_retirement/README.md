# Retire unpublished vegetation invalidations — 2026-10-18

An exclusion invalidation marks wanted cells dirty even before first publication.
The camera-cell retirement loop previously erased dirty entries only when a cell
had a resident entry. Leaving before publication stranded old dirty cells outside
the wanted set. Those cells could not be serviced and prevented a settled state.

Production now removes obsolete dirty entries when the wanted region changes,
including cells that never published. This is bounded bookkeeping on cell changes;
no candidate count, model, shadow, render budget or persistence format changes.
Gathered/placed records remain owned by the unchanged persistent state component.

A deterministic regression invokes the real invalidation method during initial
loading, then teleports before the reply. It fails on the old implementation and
passes after correction; all92 existing/new streaming checks pass. Logs retained.
The integrated readonly seed42 southern world also passes after deliberately
invalidating unpublished cover immediately before destination travel. All49 owners
settle and all species have zero budget-deferred pages, at1920x1080 cap60.

This proves the stranded-dirty-entry defect and its correction. The earlier
intermittent failure did not record owner state, so exact attribution remains
unproven. Detailed half-second owner/request/job telemetry now accompanies failures.
No steady60, thermal, long-run or vegetation art acceptance is claimed. Regular
spacing and weak daylight integration remain separate visual work.

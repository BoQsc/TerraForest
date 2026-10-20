# Default paging compatibility and startup autosave - 2026-10-20

A temporary default-on configuration was exercised, then withdrawn because the
arrival gate is not reliably met. Production remains opt-in (--model-region-paging)
with an explicit --no-model-region-paging diagnostic override. No user saves
were edited; persistence checks use paging_integrated_20261020.

Compatibility results: full-resident fallback startup, paged prefab-only model
edit, normal save, exact fresh-process restoration and travel all pass functional
checks. The normal browser launch-policy creation/reopen test also passes with
the temporary default-on configuration. Native lifecycle regression passes.
15 preparation orchestration tests pass; these mock generation subprocesses and
are not a full district-generation rerun.

The writable route exposed automatic saving at the end of initial loading:
autosave_timer counted loading time, so a long startup immediately captured a save
(72.61 ms main-thread capture) before first travel, delaying central arrival to
1932 ms. The player controller now pauses the automatic-save clock and submission
while its loading screen is active, and resumes it when ready. Manual save and
shutdown saving remain available. Standalone terrain-addon behavior is preserved:
autosave_paused defaults false rather than relying on an externally cleared
initial_loading flag. Corrected writable test has no startup autosave; edit/manual
save/shutdown succeed. The separate browser create/reopen also passes the final
explicit pause-hook implementation.

Offline combined generation explicitly opts into full model residency because
its verifier compares complete world snapshots; a local paged subset cannot be
used as whole-world evidence. Normal gameplay remains separate from this offline
verification mode. Full multi-minute composition was not rerun for this guard.

Fresh reopen still recorded northern arrival 1102.826 ms, with zero missing nearby
records and correct visual/collision readiness. Thus the earlier two sub-second
runs do not establish a reliable bound. The full route report is intentionally
FAILED on timing. Default enablement is deferred, not silently accepted. Prior
43.523 ms frame spike and save-capture cost also remain unresolved.

Next: assess realistic travel/loading workloads and remaining save/arrival stalls
before default promotion. Preserve the corrected readiness and save integrity;
do not keep increasing budgets to chase a single benchmark.

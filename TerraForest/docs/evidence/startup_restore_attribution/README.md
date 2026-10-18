# Startup restore attribution — 2026-10-18

Split terrain receive into queue polling and per-result-kind elapsed timings, and compound restoration into named provider timings. Existing main-thread behavior, ordering, readiness and save data are unchanged. Provider timing is conditional on the host exposing the existing stage recorder, retaining compatibility with alternate hosts.

The copied populated-world startup trace attributes 121.187 ms to volumetric_water restoration, within a 135.179 ms startup reply and 136.941 ms total receive phase. Largest mesh reply0.060 ms, queue poll0.026 ms, structures restore0.557 ms, actors0.109 ms, player loadout2.845 ms. These are nested elapsed timings, not additive CPU samples. Startup completes and both residents restore. Source hash remains unchanged in run.json.

This identifies the dominant component of the recurring receive stall; it does NOT explain the earlier1.39-second controller-process event. The user deferred water, so its implementation and scheduling are unchanged. Record water restore as a deferred loading cost, and avoid misattributing this trace to terrain mesh receipt or actor population. No performance fix or60FPS qualification is claimed.

Reproduce with `python tools/run_populated_startup_trace.py --source populated_review_20261016`. An initial attempt at inserting instrumentation failed due mixed line endings and accidentally ran the unchanged trace; that run remains locally at reports/populated_startup_trace/20261018T034751087290Z and is not used as attribution evidence. The corrected instrumented run is recorded here. The final optional-host guard was inspected without repeating the unchanged whole startup check.

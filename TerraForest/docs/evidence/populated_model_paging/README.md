# Populated-world model paging - 2026-10-20

Production defect found and fixed: prefab-only stair rails were omitted from the
native edit journal because it was configured from the placement UI catalog.
The paging scheduler nevertheless registered those collections, causing repeated
transfer_rejected admissions and missing saved models. The world now supplies all
registered model collections to the native history, without adding prefab parts
to the placement UI. The existing native transfer path is unchanged.

A bounded last_failure record is exposed alongside transfer counts to preserve the
asset, region and native rejection reason instead of losing diagnostic context.

## Actual-world evidence

Source southern_mixed_42_20261018 was cloned to paging_integrated_20261020. Source
SHA256 remained 3a76b6fa3e86aecf6c529263d22cf59174d73644dcb67d21b8332c4048ed4995.
No user save was edited. The disposable clone contains the intentional rail edit.

Test tests/populated_model_paging.gd runs in the actual world at fullscreen
1920x1080 capped at 60. Non-paged baseline records 995 saved model transforms.
Paged travel visits central, north, south, central. Every saved model within 128 m
must have its exact ID/transform restored; distant unloaded regions must exist.
The original run failed seven checks; diagnostic run identified stair rails.
Corrected travel passes with zero transfer failures. The test then moves stair
rail 1 upwards 0.125 m through the real native journal and saves through the normal
paged lifecycle. A fresh process repeats the full route and matches the updated
manifest. All checks pass. Timings in run.json are test durations, not frame gates.

Baseline arguments: --snapshot-readonly --world-slot=paging_integrated_20261020
--ground-cover --actors --vehicle-fleet --gameplay-construction.
Add --model-region-paging for travel. For the disposable clone only, replace
--snapshot-readonly with --edit-check --diagnose-first to exercise editing/save;
then rerun the read-only full route in a fresh process. Use a fresh clone and
baseline when repeating; the fixture intentionally changes a rail each edit run.

## Limits and next gate

This proves actual saved model record admission/retirement and a prefab-only edit
across save/reopen. It does not prove model collision availability at the instant
loading finishes, visible continuity, high-speed predictive loading, strict frame
budgets, storage growth or arbitrary city capacity. No art acceptance was inferred.
Model paging remains opt-in until destination collision/render readiness and
arrival/frame bounds are checked in the combined world. Do not skip this gate.

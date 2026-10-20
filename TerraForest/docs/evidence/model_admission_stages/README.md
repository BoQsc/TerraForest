# Bounded admission stage advancement - 2026-10-20

Completed reads may now proceed through local admission stages in the same native
tick, with operation/time checks before each stage. No additional disk waits.
The production scene allows 16 cheap operations rather than eight, retaining
256 records, 64 KiB hashing and 500 microsecond requested CPU budget per tick,
eight jobs and the existing memory limits. This uses more of the existing time
budget; it is not a promise that every non-preemptible call ends under 500 us.

The local-stage change alone yielded north 1198 ms: insufficient. Combined with
the operation allowance it gives the following actual-world 1080p cap-60 results:

| Destination | First ms | Repeat ms |
|---|---:|---:|
| Central | 63 | 48 |
| North | 972 | 966 |
| South | 549 | 484 |
| Return | 633 | 667 |

Both runs pass zero missing nearby records, published pages and local collision
before loading releases, exact saved transforms, zero failed transfers and bounded
far-record retirement. Native scheduler cancellation/budget and focus tests pass.
The repeated route explicitly checks operation/record/hash limits. Observed native
arrival-step maxima were 440 us first run and 331 us repeat. Source saves were not
changed. Native debug/release builds updated; graphical checks use debug.

The one-second arrival gate passes for these two routes, with little margin at
north. It is now an explicit assertion in the reusable route test (the same
recorded values were checked when adding it). This is not a general latency bound.
Post-admission max frames were <=16.955 ms, but these are short samples excluding
loading. The prior 43.523 ms frame remains unresolved; no sustained 60 FPS claim.
Raw frame traces remain in reports/populated_model_paging; compact summaries here
retain measured bounds without duplicating thousands of telemetry lines.

Next: normal launch/default-paging compatibility and populated-world save/reopen
with the final scheduler settings, then combined travel frame attribution. Do not
restart unrelated asset tuning or treat this gate as completed world qualification.

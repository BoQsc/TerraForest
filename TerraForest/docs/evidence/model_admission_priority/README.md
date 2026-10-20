# Foreground model admissions - 2026-10-20

Short actual-world tracing showed the eight-slot scheduler busy with many small
read/admission/retirement operations during arrival. Northern arrival required
about 104 frames/735 scheduler operations, rather than one long CPU task.

Automatic retirement now occupies at most one quarter of scheduler slots (at
least one); the production eight-slot configuration permits two concurrent
retirements. Incoming content can use the other slots. Explicit scheduler requests
retain their API contract. Job, byte, per-tick operation and time budgets did not
increase. Existing readiness gates remain unchanged. Both native builds updated.

Actual populated 995-model route at fullscreen 1920x1080, cap 60, read-only copy:

| Route | Baseline ms | First modified ms |
|---|---:|---:|
| Central | 41 | 47 |
| North | 1782 | 1215 |
| South | 1195 | 467 |
| Return | 789 | 783 |

Both modified runs pass exact nearby ID/transforms, zero missing records at
loading release, native visual/local collision readiness, retirement and zero
transfer failures. Native focus-paging regression passes. The repeated route also
requires every resident record farther than 600 m to retire within a ten-second
bound after travel; it passes. This is a bound for this small fixture, not general
world-scale residency or memory endurance.

Tradeoff: retirement is slower. First-run north/south/return resident counts after
the short settling window are 543/259/365 versus baseline 509/56/332. The explicit
retirement drain check is retained rather than hiding that transient increase.

Detailed repeat timings are in foreground_repeat_result.json. Post-admission
frame samples exclude loading; they cannot certify travel frame pacing. Timing
variance remains possible. The northern arrival still exceeds the 1000 ms gate:
keep paging opt-in and continue latency attribution. No sustained 60 FPS,
high-speed vehicle or city-scale capacity claim. No user save was modified.

Repeat north/south/return: 1265/482/750 ms. The repeated central post-admission
sample includes a 43.523 ms frame, retained as a frame-pacing failure requiring
attribution; do not infer stable 60 FPS from the other short samples.

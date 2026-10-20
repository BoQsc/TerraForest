## Native collection retirement; optimization stopping point — 2026-10-20

Native transient vegetation collections now detach once and retire in bounded record
steps, including members of large nested groups. New rendering waits for old pages;
reused placement IDs remain independent. Native and ground-cover regressions pass.
The integrated readonly 1920x1080 reload passed: initiation 5.903 ms, 33 preparation
frames, largest preparation slice 2.530 ms, largest restoration slice 3.289 ms.
These are scoped observations, not hard timing or long-run thermal guarantees.
Evidence: `evidence/transient_collection_retirement`.

**Direction correction:** this work did not generate new world content. Stop further
reload optimization now. The next deliverable is visible improvement to the integrated
generated region, reviewed against WORLD_BUILDING_STANDARD.md: terrain-fitting varied
settlements, connected roads and purposeful explorable locations. Existing outstanding
performance, storage and endurance requirements remain open; test them alongside world
changes rather than making further micro-optimization the next content milestone.


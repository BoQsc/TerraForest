# Shoreline query disagreement: retained failing baseline

2026-10-11, runtime c513231. This checkpoint adds diagnosis, not a runtime fix.
`tests/water_shoreline_queries.gd` takes under two seconds headless. The six checks
include one intentional unmet correctness gate; the suite exits1, not a passing
baseline. Run with `python tools/run_godot_check.py water_shoreline_queries
--headless --timeout 10 --require failures=0`.

The fixture uses a known concave quadratic basin sampled into the real native
builder. Samples are barycentric points below actual smooth surface triangles,
retained only when analytic air clearance exceeds0.05m. This margin exceeds the
quadratic interpolation error in this unit grid, avoiding false reports inside
terrain. Counts are triangle samples, **not area percentages**.

| Depth below surface | Visible/free-space samples | Incorrectly dry queries |
| --- | ---: | ---: |
|0.1m|718|646|
|0.6m|175|103|
|1.1m|84|36|
|2.0m|62|14|

Cold and restored bakes classify identically. Outside-basin and solid-floor points
stay dry. Native whole-cell eligibility requires all eight corners to be air;
partial boundary cells therefore lose usable water even when their query point is
inside free space. Smooth rendering independently extends toward the true shore.
This is a representation mismatch, not a cache corruption or rendering-only defect.

`cross_section.png` is an independent uniform0.25m X/Z sampling plane at1.1m depth:
green detects water, orange is analytic free space reporting dry, dark is solid or
the excluded0.05m margin. The 128x128 grid values are retained in result.json. The
plot uses analytic basin membership rather than computing per-pixel mesh coverage;
the separate triangle sample assertions establish visible-water disagreement.

No terrain/world binary changes and no user save changes. This does not quantify
all natural shorelines, gameplay movement error or GPU cost. Existing cave tests
must keep passing when the query representation changes.

Implementation decision and gates: ../../WATER_BOUNDARY_QUERIES.md.

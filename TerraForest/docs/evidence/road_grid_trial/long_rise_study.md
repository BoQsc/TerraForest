# Long-rise road study — 2026-10-25

The user proposed distributing road elevation over a much longer distance so
the grade is almost invisible and placed blocks sit slightly below the surface.
This study tests that distinction before changing any generator or player save.

## Result

Lengthening a full one-metre rise improves slope smoothness but does not remove
its fractional-height mismatch with the one-metre building lattice. At height
35.5 m, a full cube has its bottom at either 35 m (half buried) or 36 m (half
floating). A low gradient only reduces height variation across that cube;
it does not change these permitted bottom heights. The existing 20 cm burial
allowance intentionally avoids the half-buried choice.

The promising distinction is a **long near-level street**, whose total variation
stays in a narrow band above one grid level, rather than an indefinitely rising
street. It can have subtle drainage/grade while blocks overlap by 5–15 cm.

| Isolated native road | Maximum grade | Midpoint contact | Footprints within 15 cm air gap |
| --- | ---: | --- | ---: |
| 1 m rise over 15 m | 10% | 46.2 cm air gap | 7 / 15 |
| 1 m rise over 100 m | 1.5% | 42.6 cm air gap | 51 / 99 |
| 10 cm rise over 100 m, starting 5 cm above grid | 0.15% | 10.1 cm burial | 99 / 99 |
| Level street 8 cm above grid | 0% | 8.0 cm burial | 99 / 99 |

The latter two cases had no measured air gap anywhere sampled; maximum burial
was 15.04 cm and 8.01 cm respectively. These are 312 individual one-metre
footprints, each using the existing nine-ray native collision-support query.
Boundary footprints extending outside a segment are not included; this is not a
survey of shoulders, intersections, turns, or every point on the surface.

`long_rise_comparison.png` is an inspected 1920×1080 engine render. Each panel
uses its actual native volumetric road mesh/collision and an ordinary native
brick at the grid coordinate returned by the current targeting support logic.
The roads use cubic smooth transitions; the first two endpoints differ by a full
metre. The 8 cm offset is already consistent with the accepted build-friendly
terrain principle. No target offsets, burial allowance changes or new blocks.
This is a controlled isolated study, not a claimed replacement settlement.

## Consequence for the next preview

Plan long near-level street sections around building frontages, with their
whole intended building strip inside roughly integer+0.05 to integer+0.15 m.
Plan the unavoidable elevation transitions between those sections, preferably
away from the principal frontages. Those transitions can be smooth and gradual,
but cannot simultaneously promise shallow burial/no gap at every location while
crossing full vertical grid levels. Do not ban player building there.

More gradual transitions use more horizontal space; they must be routed and
surveyed against real terrain, not obtained by flattening an entire town or
relaxing the 2 m fill / 3 m cut budgets. House thresholds, individual sidewalk
plates, intersections and shoulders must be co-planned before baking.

This does **not** approve or enable the earlier small-remapping trial. The next
frontage-aware layout preview is still pending, including real-world terrain-fit,
entrance/plate continuity, traversal, complete-world save/reload, generation cost
and human review. Neither isolated result proves those requirements complete.

## Reproduce and scope

```
python tools/run_godot_check.py road_long_rise_study --headless --timeout 90 --require "ROAD_LONG_RISE_STUDY failures=0"
python tools/run_godot_check.py road_long_rise_study --timeout 90 --require "ROAD_LONG_RISE_STUDY failures=0"
```

Outputs: `reports/road_long_rise_study/measurements.json` and `comparison.png`.
Passing headless run: `reports/checks/20261025T154722865932Z`.
Passing graphical run: `reports/checks/20261025T154743028145Z`.
The initial fixture used a non-supported mesh vertical interval and failed all
four mesh requests; it now uses the native aligned 32–64 m interval. That failed
run remains at `reports/checks/20261025T154642728318Z`.

Only tests/evidence are added. No native library, normal generation recipe,
placement code, exported gameplay pack or saved world is changed. All roads in
the fixture are generated in separate in-memory empty terrain fields. No
runtime-performance or human acceptance claim is made.

# Road-grid grading trial — not approved or enabled by default

User request: reduce conspicuous gaps through road/terrain generation, preserve
the metre block lattice and intentional floating construction, preview first.
Also identify the loaded world in ordinary screenshots without redesigning HUD.

## Diagnosis and isolation

Latest closed player save: **Wild_Hills, seed 1703, terrain profile 21**, two
connected settlements, standard network and trails. The existing build-friendly
base generator does not reshape baked road grades. Integer street nodes do not
make every point on the intervening cubic ramps an integer height. Regional and
trail nodes can have fractional grades too. This is not a placement-delay bug.

The read-only saved-world audit records the actual player pose, generated region
and density hits, not just undeveloped terrain heights. It does not prove the
exact camera location of the supplied screenshots. The player had moved away;
the comparison uses a nearby sloped street in the same saved settlement.

No original save or sidecar is regenerated or overwritten. The world preview
requires both `--temporary` and `--snapshot-readonly`; its wrapper hashes every
Wild_Hills file before/after. Road edits and temporary test bricks exist only in
memory. Existing player blocks are not repositioned. Accepted houses, trusted
flat sidewalk plates and normal generation calls remain unchanged.

## Experimental implementation

`NativeRoadProfile.grid_trial` remaps a supplied cubic road-height chain toward
integer landings, retaining smooth transitions. It preserves chain endpoints
and endpoint tangents, tapers the adjustment near ends, and analytically checks
cubic extrema. The trial limits displacement to 0.30 m and grade to 16%; roads
already above that grade remain unchanged. This **can steepen** portions of an
otherwise gentle ramp. These limits are experimental, not an accepted road
standard or an earthworks approval.

The native method emits at most 64 cubic sections. The scaffolding converts
those into the existing editable volumetric-road command, preserving material,
width, depth and shoulder. No new meshes, building shapes, per-block offsets,
placement restrictions or per-frame terrain logic. Ordinary binary terrain
snapshots retain the result without a new save format.

The adapter is **not called by normal generation/loading**. Run it explicitly
through the review tool below. There is no production world-generator toggle
yet, because the design has not earned promotion. Normal worlds do not change
merely because the native library contains this callable experiment.

For the seed-1703 whole plan, 58 road segments receive adjustments. The equivalent
earthworks command count grows from 316 to 1,178; the reported maximum profile
shift is 0.2723 m and maximum grade 16%. That extra offline bake work is a known
cost, not an efficiency win. Before production integration, reduce redundant
stamps and measure complete generation time, memory and cache behavior.

## What the comparison actually shows

Road: `(1003.667, 35, 1093)` to `(1018.333, 36, 1093)`.
Three newly targeted test bricks use the real placement handler in both views;
the additional existing player brick remains untouched. The left test brick at
`(1007, *, 1093)` changes from a 0.859 m visible gap to contact with at most
0.151 m burial, under the unchanged 0.20 m placement allowance. Its bottom moves
from grid level 36 to grid level 35: **no off-grid adjustment**.

Across 42 one-metre footprints (three lateral tracks, nine collision samples
per footprint), the initial comparison measured:

| Measure | Original | Trial |
| --- | ---: | ---: |
| Footprints with gap at most 15 cm | 19 | 21 |
| Footprints with gap above 50 cm | 13 | 11 |
| Mean gap | 31.1 cm | 27.0 cm |
| Worst gap | 86.5 cm | 83.9 cm |

This is **modest improvement, not a solution for all roads**. The middle test
brick still floats about half a metre on a transition; the full-stretch report
deliberately retains that failure case. The road and landscape remain visually
continuous in the inspected close and overview renders, but gaps remain too
large to claim universal block friendliness. Do not enable it by default.

Images are real 1920×1080 engine renders in a continuously updating SubViewport,
not generated artwork. Frame counters during edits/readback are not a gameplay
performance benchmark. `before.png`, `after.png`, `after_overview.png` retain the
loaded-world HUD line and explicit preview label.

## Reproduce

From the TerraForest directory, with the player game closed:

```
python tools/check_road_grid_preview.py
python tools/run_godot_check.py saved_road_grid_audit --headless --timeout 120 --require ROAD_GRID_AUDIT -- --inspect-slot=Wild_Hills
```

The first tool prepares/validates the native profile in a completed headless
process, then runs one graphical comparison process. It does not launch a second
background game during play. Outputs and source hashes are under
`reports/road_grid_trial/`; the tool intentionally targets this reproduction save.

Checks cover invalid inputs, deterministic fitting, endpoint anchors, analytic
limits, immutable default packets, ordinary density baking/snapshot roundtrip,
actual streamed collision and placement, complete-footprint contact statistics,
floating face attachment, loaded-world HUD identity and source-save preservation.

Retained local failed attempts: the first renderer captured the destination
loading screen because it waited for local collision only; the revised fixture
also waits for the landscape and hidden loading layer and checks this at every
capture. Another fixture used material index 1 while asserting brick word 1;
it now uses brick material index 0. Neither failure altered production placement
or the original save. Failed run folders remain in reports rather than being
silently counted as visual evidence.

The first additional packed-native check tried to write reports through the
read-only `res://` archive. The fixture now globalizes its output directory;
the repeat passes against the installed pack. This was a test-output error, not
a generation failure. Source and packed native trial checks, original road
profile/road-bed checks, default plan-cache checks and world-recipe/flat-plate
regressions pass. Both native DLL variants are rebuilt and the exported pack
passes startup. `validation.json` records the scoped evidence.

## Open acceptance gates

Human appearance/playtest approval is pending. Frontage-aware road planning and
longer usable level stretches are still needed; small height remapping alone
does not remove mid-ramp gaps. Before wiring a user-facing generation option,
survey whole footprints against original cut/fill budgets, verify entrances,
shoulders, bends, intersections and all road classes across more seeds, then
walk/drive and save/reopen complete generated worlds. Preserve smooth ramps,
interesting terrain, accepted plate shapes, and all existing saves throughout.

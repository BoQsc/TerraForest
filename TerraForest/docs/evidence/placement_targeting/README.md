# Ground-aware placement targeting

2026-10-24. The old block target floored the clicked ground height, allowing most
of a cube to disappear into terrain. Object placement snapped X/Z after one hit
without resampling the new footprint, allowing uphill ground to cover furniture.

`NativeBlockWorld.placement_support` now checks a fixed 3×3 inset footprint using
short vertical physics rays and authoritative native block geometry. The native
query runs on the physics owner thread; it creates no worker, terrain bake, saved
cache or world scan. Footprints, coordinate range and exclusion inputs are bounded.
The existing preview cadence remains 10 Hz, and clicks repeat the fit before
inventory transactions. Unknown collision is rejected rather than assumed empty.

- Single grid blocks allow 20 cm of sampled ground overlap, reduced to 25% of
  height for thin shapes. Deep overlap advances to the next integer Y cell.
  Existing block-face targeting retains its exact adjacent cell and rejects
  excessive surrounding soil instead of silently detaching a wall from its support.
- Objects fit the highest sampled surface after X/Z snapping and rotation. Their
  base overlap is limited to 3 cm or 10% of height, whichever is smaller. Initial
  vertical correction is capped at 0.8 m and sampled support gap at 0.6 m.
- Whole-cell fits advance at most one cell and reject sampled gaps over 1.15 m.
  Preview validity and click acceptance use the same result. Rejection happens
  before payment; the existing player/instance/paid-insertion guards still apply.

These are initial targeting rules, not a complete structural support simulation.
The nine samples can miss small features between them; vertical queries cover
1.5 m above/below the aimed height. Grid snapping may leave ground gaps. No terrain
cut, fill or density/material mutation is performed. Automatic enclosure/filling
is deferred per the user; prefab surveys and explicit transform controls retain
their separate behavior. This does not qualify generated settlement terrain fit
or final gameplay feel on all landscapes.

Validation records and inspected captures are retained in this directory. The
temporary world tests include a real streamed forest placement and deterministic
flat/sloped collision fixtures. The pictures hide the next-placement ghost after
checking preview agreement so that the published block/object is visible.

All **90 assertions** pass across these final runs:

| Record | UTC run ID | Assertions |
| --- | --- | ---: |
| [Debug native](source_native/console.log) | `20261024T094735099925Z` | 14 |
| [Release native](release_native/console.log) | `20261024T095734931548Z_placement_release` | 14 |
| [Source gameplay](source_gameplay/console.log) | `20261024T095527472909Z` | 17 |
| [Development input](development_input/console.log) | `20261024T095555421823Z` | 28 |
| [Packaged gameplay](packaged_gameplay/console.log) | `20261024T095724620974Z_placement_pack` | 17 |

Source and packaged captures were inspected at 1920×1080. The forest cube remains
visible above the real terrain. The controlled 0.82 m ground fixture leaves a
visible 0.18 m gap below a whole-cell cube, as expected from the preserved grid;
the sloped table has slight overlap at the uphill support and clearance beneath
its downhill side. This is not seamless terrain enclosure. Export/startup passes
with fourteen external native libraries. The updated source and dist libraries
are installed locally.

Reproduce:

```powershell
python tools/build_native.py --addon structures --target all
python tools/run_godot_check.py placement_support --headless --timeout 40 --require 'failures=0'
python tools/run_godot_check.py placement_targeting_world --timeout 110 --require 'failures=0' -- --gameplay-construction --no-zombies
python tools/run_godot_check.py construction_interaction --timeout 100 --require 'PASS clear removes selection and all markers' -- --no-zombies
python docs/evidence/placement_targeting/check_release.py
python tools/export_pack.py --godot 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot Engine.exe'
python docs/evidence/placement_targeting/check_pack.py
```

Only run the last command after export finishes. The release check uses a clean
temporary project containing the release structures DLL. The packaged check uses
an external assertion helper; game scenes/scripts/assets resolve from the exported
PCK and dist libraries. Manifests record test, engine, native library and pack
hashes where applicable. These checks are correctness evidence, not an aggregate
performance qualification.

Failures retained: an initial forest assertion disabled physics before the player
had settled from the spawn height; the fixture now explicitly waits for floor
settling. The older construction regression selected a historical toolbelt slot;
it now activates the current development block tool and waits for support collision
readiness before expecting a green preview. Both failing runs and their corrected
passes are preserved. The first DLL installation attempt encountered the running
game's Windows file lock; after the user closed the game, both variants built and
installed successfully. This was a library-replacement issue, not a compiler error.

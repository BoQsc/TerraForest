# Blackridge coal mine

- Status: Source prototype; scoped journey and fresh-process persistence verified. Packaged and visual acceptance pending.
- Updated: 2026-11-01. User visual review: not reviewed.
- Brief: a mountain-embedded mine, short sleeper/chest dead ends, a longer rail
  loop, varied chambers, and a deeper station structure containing ten zombies.

## Images

![Current generated station with ten sleepers](images/station-current.png)

Fresh default generation, seed 1703, `CoalMine_1703_2db6d4b4`, source build,
1920×1080. Inspected after real chest transfers and rail construction. This run
completed the inside route; the final hillside elevation assertion was corrected
and checked in a separate continuation below. HUD FPS is not a benchmark.

![Grounded return to the hillside with harvested coal](images/exit-current.png)

The same owned world, targeted final-exit continuation and fresh-process reopen:
13 and 41 checks pass. Depleted chest contents, dead station resident, ten stable
station identities, harvested coal and exact rail transforms restore.

Historical captures follow; their original failed-run scope is preserved.

![Deep loading station in the generated world](images/station-world.png)

Default Generate & play, seed 1703, `CoalMine_1703_23e94d31`, source build,
1920×1080 offscreen capture. Ten station residents and the timber loading canopy
are physically present. The assistant inspected this image. This capture belongs
to the retained run that later hit a test-script error; it is not full-run or
performance acceptance. Screenshot HUD FPS is not a benchmark.

![Isolated station view](images/station-fixture.png)
![Return-loop gallery](images/loop-fixture.png)
![Mine entrance](images/entrance-fixture.png)

Native natural-hillside fixture, seed 1703, origin `(536,139,445)`, rotation 3,
1920×1080. The shared foundation/grounded-model publication checks pass. These
fixture images were inspected for rail continuity, station clearance and terrain
contact. They omit surrounding vegetation and normal world presentation.
Sources, captions and hashes: [image manifest](images/manifest.json).

## Implementation

The default new-world recipe now surveys a third underground layout through the
existing bounded native hillside planner. It fits only where the roof stays
covered, the approach remains dry and within earthwork budgets, and other sites
are excluded. A failed search records a skipped layout; it does not force a site.
Existing saves retain their contents and are not repopulated.

The mine has 16 authored excavation passages, two short supply branches, a
return loop, a large working chamber and a loading station roughly 50 m inside.
The portal door, timber frames and station roof/posts/benches are native block
and model placements. Five stocked chests and 13 keyed inhabitants belong to the
location: three side encounters and exactly ten station residents. Stable keys
use bit 42 for this mine and bit 43 for station residents, in addition to the
existing underground ownership bit. Quest ownership uses the existing registry.

Rails are five reusable construction models: 4 m straight, 2 m straight,
90°/45° bends at 4 m radius and a turnout. The gauge is 1 m. Curves are sampled
offline, with thin foot/web/head profiles and timber ties. Low compound proxies
are inset at joins and all models share native batched rendering, damage,
salvage and persistence. The portal and chamber transfer have intentionally
broken track. Coal heaps are original harvestable models; item 220 is Coal.

The station requirement needs more than the previous six-body cap. Native
awareness/navigation reserve a bounded 16 slots; ordinary population admission
stays at six. A nearby coal-mine key enables up to 16, enough for all 13 mine
residents and three other residents. Route search work budgets are unchanged.
This is not a general increase in ambient population or a dense-crowd performance
approval. No independent AI controller or new movement integrator was added.

New code is 0BSD; original model/layout/icon data is CC0-1.0. Editable source and
exact asset scope: [provenance](../../addons/exploration/COAL_MINE_PROVENANCE.txt).
Inherited timber, chest, door and character terms remain intact.

## Verification and retained failures

- `reports/checks/20261101T173801885550Z`: 38 native coal-mine assertions pass,
  including native publication, paired 45-degree rail joins, exact rail/population
  restoration and explicit awareness capacity rejection above 16. The earlier
  36-check report remains at `reports/checks/20261101T171259467558Z`.
- `reports/exploration_native/20261101T171924310635Z`: release arched excavation,
  all-layout/five-seed/all-rotation terrain checks, and model-only publication pass.
- Awareness: 34 debug and 34 release checks pass, including admitting sixteen
  station slots and rejecting seventeen. Debug evidence:
  `reports/checks/20261101T173808804319Z`. The original six-slot configured fixture
  still rejects a seventh record.
- `reports/coal_mine/20261101T171449512743Z`: rendered fixture passes all support,
  placement, sleeping-envelope and actual wake checks, including all 13 residents.
- `reports/coal_mine/20261101T171812493734Z`: normal Generate & play created and
  durably published the mine; physical player walks reached both loot branches,
  completed the loop, opened the door, and reached the deep station. All ten
  station bodies were present and completed waking. Later failed on the driver's
  nonexistent `inventory.count` call, now replaced by counting native snapshot
  slots. Its owned save was reused by the next retained run.
- `reports/coal_mine/20261101T173811247298Z`: paid rail placement, chest transfers,
  loop, ten station bodies/wakes and coal harvesting pass. The straight return
  hit an awake resident frozen in the central aisle by the test. This is retained
  crowding evidence; it is not a performance or combat pass.
- `reports/coal_mine/20261101T174028166898Z`: fresh default generation and the
  complete mine route pass using the existing station side lane. The last exterior
  walk reached its X/Z target and stood on the hillside at Y138.07, but the test
  incorrectly required the tunnel's Y139. That assertion failed; the owned world
  saved durably. Exterior checks now require grounded arrival instead of a flat
  tunnel elevation. The failed report is retained, with a separate continuation
  for the exit and fresh-process persistence checks.
- `reports/coal_mine/20261101T171539657228Z`: stopped after repeated concurrent
  terrain script/DLL signature mismatch; the source native terrain build was
  brought into agreement. This is a failed run, not mine traversal evidence.
- Initial native reports retain the rejected curved-proxy joins and insufficient
  full-envelope floor excavation. Those failures were corrected by clamping
  endpoint proxies and authoring larger turning chambers; acceptance checks were
  retained. The first rendered review also used a stale six-capacity native
  awareness build. No failed logs or screenshots were discarded.

- `reports/coal_mine/20261101T174529753475Z`: targeted exterior continuation
  passes 13 checks; fresh-process reopening passes 41 checks. The preceding
  ordinary generation and all interior movement remain evidenced by the retained
  `174028166898Z` run. This is combined functional evidence, not an uninterrupted
  all-green generation-to-reopen run. The continuation loaded concurrent combat
  hooks without errors; a frozen packaged build remains a separate gate.
- Sampled source resource peaks across generation/exit/reopen stayed within the
  repository gates: at most 3,907,481,600 bytes private commit and 1,493,803,008 bytes
  dedicated GPU allocations. Offscreen samples do not establish frame pacing.

## Remaining / resume here

The next shared export requires the vehicle, camera and combat source owners to
agree on a freeze. Then run the corrected ordinary generation-to-reopen journey
against that matching pack with `python tools/check_coal_mine.py world --pack`.
No mine build has replaced the installed pack. This also supplies one uninterrupted
passing run after the driver fixes; current source functional evidence is combined
across the retained normal journey and its targeted exit/reopen continuation.
These remain open release gates, not completed installation claims.

Player review should assess station repetition, mine dressing and branch variety.
The inspected prototype has a deliberately simple timber canopy and symmetric
station seating; this is not final location-art acceptance. Foreground frame
pacing with all ten awake, combat/crowding, broader generated-world seeds and
long-run performance remain unqualified. Native route and sleeper checks alone
do not qualify whole-world pursuit or every possible terrain encounter.

## Reproduce

Use a new default **Generate & play** world, seed **1703**, then find **Blackridge
coal mine** on the map. Existing worlds do not acquire it automatically.

Safe owned test commands, run from the project directory:

```text
python tools/run_godot_check.py coal_mine --headless --timeout 90 --require "COAL_MINE checks="
python tools/check_exploration_native.py --release
python tools/check_coal_mine.py review
python tools/check_coal_mine.py world
python tools/check_coal_mine.py world --retry reports/coal_mine/20261101T174028166898Z --complete-return
```

The world driver creates only `CoalMine_*` test worlds, uses ordinary browser
generation/loading, disables desktop pointer capture and runs nonactivating.
Travel from the town to the mine is not tested: it streams to the approach, then
uses the real walking controller through the mine. Existing player saves are not
used. The retry option validates ownership before opening a retained test world.

The diagnostic `--complete-return` mode checks only a retained journey’s final
exterior walk and persistence. It does not relabel that earlier failed run. The
regular `world` mode exercises the corrected full route from a new default world.

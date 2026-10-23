# World workflow redesign

User priority, 2026-10-22: stop mine/POI detail work. Deliver a unified world
generator, selector, loading screen, map, baking/cache and storage foundation before
returning to gameplay inconsistencies. This is a required workstream, not completed
by the first UI changes.

## Acceptance scope

1. One ordinary launcher. Historical commands remain in a clearly separate folder.
2. World selector with last-played/creation ordering, understandable world identity,
   images and saved settings. Never change an existing world's generation on open.
3. Loading background randomly selected from cached real views of that world.
   Capture offline, without HUD or hands. No extra continuously rendered scene.
   Existing worlds without previews need a supported refresh path; first-generation
   loading needs an honest placeholder until an actual world image exists.
4. Generator UI with map and useful options. Preview and final bake must share the
   same versioned plan, including terrain, settlements, roads, buildings and POIs.
   A terrain-only preview must not imply those placements are already planned.
5. Heavy generation/planning executes in native jobs. Use compute shaders for
   suitable parallel field/tile work, with bounded submission/readback and measured
   equivalence to the authoritative representation. GDScript handles UI, job
   coordination and future modding only. Current scripted lot/route loops are not
   accepted as the final native generator.
6. Staged bake jobs: terrain/biome fields, region layout, roads/sites, building
   placement, collision/LOD products, map and preview assets. Enforce dependency
   order, cancellation, progress, bounded memory and reproducible seed/settings.
7. Versioned authoritative manifest and regional storage, derived cache identity,
   quotas, atomic publication/recovery, selective loading and retained distant edits.
   Separate regenerable cache from authoritative edits. No capacity increases to
   disguise unbounded residency. Keep existing saves readable.
8. Integrated proof: create, preview, bake, cancel/recover, open, travel, edit and
   save/reopen; inspect 1920x1080 visuals and record CPU/GPU/frame/memory costs.
   Short correctness tests precede any endurance run.

## Current implementation and remaining work

- Root launcher consolidation and date sorting implemented. New preparation records
  creation time; successful first playable admission records last played. Legacy
  worlds with no metadata fall back to save modification time, explicitly labelled.
- Selector now has separate library/create tabs and a worker-based native terrain
  survey preview using the existing verified cartography cache. It is terrain only:
  planned roads, settlements, ocean coverage and final layout preview remain open.
- Bounded cached loading photos are supported. Preparation captures three views;
  loading chooses one. Existing-world capture utility works read-only. Automatic
  existing-world refresh/discovery and complete creation pipeline verification remain.
- Native generation service, compute integration, moving scripted planners to native,
  standalone generation without Python, richer generation options, shared plan/map
  identity and storage/capacity qualification remain required. No new compute
  implementation or performance gain is claimed by this UI work.

Next: establish the native world-plan API and shared preview/bake manifest, then
wire generation options and placement preview to that actual plan. Preserve working
generation until the replacement passes integrated equivalence/correctness checks.

## Parked prior work

Mine integration is stopped by user direction. A nine-case native survey found the
legacy approach needs about 3.4 m fill on seed42 and 11.8–15.7 m on coastal seeds
1703/0. The survey and offline metadata helper are retained in the Git stash named
`Park mine metadata survey after world workflow priority change`; they are not
an integrated location or approval of those earthworks. Revisit only as part of the
new world planner, after its terrain/placement contract exists.

All other open foundation requirements remain in WORLD_FOUNDATION_STATUS.md.

## Initial verification

The native terrain preview and both tabs were rendered and inspected at 1920x1080.
World-list ordering tests cover last played, creation time, deterministic name
ordering, first-play metadata updates and preservation of canonical save bytes.
The existing market world was opened read-only to capture three cached views;
the actual loading screen then displayed one of them and reached playable state.
The capture pauses the world's presentation callback for a single frame so it
cannot re-enable held hands while the HUD is hidden. No runtime world changes.

The automatic new-world capture/publication wiring has not yet received a full
create/reopen run after these changes. Existing worlds without cached photos still
use the plain fallback until previews are explicitly captured. These are open
integration tasks, not a claim of universal loading-photo coverage. No new native
planner, compute kernel, cache quota or storage migration was delivered in this pass.

## Native backend and shared-plan implementation — 2026-10-22

The previous UI-only status is superseded for road/lot computation: regional A*,
corridor checks, street grading, lot relocation/grade search and entrance fitting
now execute in the native TerrainCore. Production scripts call these APIs.
Generator preview and preparation share a versioned, bounded, integrity-checked
plan cache. Native rasterization overlays actual planned roads and lot footprints.
Full seed42 creation and fresh-process reopen passed with the identical plan
identity; new-world automatic loading-photo capture/publication was also exercised.
See [evidence and limits](evidence/native_world_generation/README.md).

The workstream remains open: native region/job orchestration and cancellation,
compute field integration, Python-free generation, complete options and water/POI
preview, canonical regional storage/capacity/recovery, and sustained performance.
Current placement recipes remain visually unfinished. The derived plan cache
must not be presented as completing canonical world storage. Next backend work
must build on this shared plan rather than recreate separate preview logic.

## Engine-owned creation and native publication — 2026-10-23

Worlds.cmd now discovers Steam Godot through tools/start_worlds.ps1; the selector
starts addons/world_runtime/generation_job.gd through the engine itself. Python is
still used for developer test/build tooling, not the player creation path. Job
creation and fresh-process verification completed for engine_generated_42_20261022.
Report: user://generation_reports/2f4c712ca1f3ccd42c2b603d9c2db927/run.json.
Native publication copied 235 files / 166080 bytes and published the root last.
The world opened in the integrated 1080p vegetation review without save mutation.

Checks: native_world_publication (20261022T204820032933Z), world_browser
(20261022T205029329633Z), generation_job_failures (20261022T210206572763Z).
Ground scatter passed 1084 assertions (20261022T210052634280Z); the earlier run
20261022T205934645481Z was marked failed by a wrong required-output string despite
zero test failures. Initial irregular-edge test indexed old/new clipped arrays by
position; corrected to match stable IDs, then passed (20261022T210138270348Z).

Open: mid-stage cancellation/recovery, publication failure at each promotion step,
exported-installation path, old-world photo refresh, complete generator settings,
water/POI preview, CPU/GPU generation work, canonical storage and large edit costs.
The full rewrite is not complete. Images do not establish resource headroom.

### Export and worker follow-through

Preparation code now lives under addons/world_runtime; tools/prepare_* retain thin
compatibility entry points. The prior export excluded tools/, so its source-only
success was insufficient. Exported PCK startup now passes and includes the runtime
preparation scripts. An explicit pack launch exposed empty globalized res:// paths;
child arguments now distinguish source projects from bundled executables. Full
standalone generation is being verified, not yet accepted by the startup check.
Native preparation leases now check the live OS handle instead of stale file
presence, allowing retry after a coordinator crash without deleting world data.

The immutable overview survey uses at most four CPU workers (half the reported
logical processors, capped at four), with one parallel batch per extension. Tiny
surveys remain serial after a measured overhead regression. Nine seed/size images
match the serial SHA256 fixtures exactly. Initial 512-square observations: serial
31–34 ms, parallel 19–25 ms on the i5-12450H. This is bounded offline survey work,
not proof of whole-generation acceleration or gameplay/thermal headroom. Stored
measurements are in evidence/native_world_generation/generation_survey_*.json.

Publication now checks filesystem inspection errors and flushes copied authoritative
files before root publication. Native publication checks pass again; failure at
each store promotion and resumption of interrupted publication remain open.

Standalone full generation now passed using dist/TerraForest.exe beside its exported
PCK and native libraries, launched from dist with no project path. Created and
fresh-process verified exported_world_42_20261023, then native publication reported
ready. Report: user://generation_reports/4eae29b10e01b540d829a15a4b14d673.
This exercised bundled resources and process handoff; it is not yet a clean-machine
release-template installer test. The first Steam-editor --main-pack attempt failed
before creation because res:// globalized to an empty path; that failure is retained
in report c9b24250da4c48d5e8371c998ea004a0. The corrected export uses its adjacent PCK.


## Generator options and route correctness — 2026-10-23

The selector now offers connected settlements, one settlement with a regional
road, or a standalone settlement. Preview and bake consume the same option flags.
Coastal preview uses the native implicit-ocean survey and visibility raster, not
an invented blue border. The 1080p generator image was inspected; the layout and
coastal overlay are readable. Actual standalone-settlement creation and fresh
process verification passed in report 525a84d5bdef1a4f30d5dd1f599c32c4.
The previously exported PCK predates these options and must be refreshed.

Native lot fitting now unpacks road descriptors once, with an exact conservative
segment broadphase. Same-machine A/B against 2320bda6 retained identical plan
hashes: seed42 6277 to 1314 ms, seed1703 3307 to 813 ms. This is an offline planning
measurement, not runtime FPS or laptop thermal evidence. See generation_matrix_*
in evidence/native_world_generation. Seed0 failed in both versions: its chosen
street exit was inside a building clearance reservation. The corrected coordinator
filters those exits and tries at most 8x8 existing street endpoints through the
unchanged native corridor validator. No grade, cut/fill or exclusion budget was
relaxed. All three seeds now plan successfully; plan cache version is 2.

Checks: generation_plan_matrix 20261023T051426676676Z;
native_world_generation 20261023T051604850049Z;
generation_layout_options 20261023T051609708935Z.
An initial diagnostic script failed on a void-valued conditional expression
(20261023T051248544190Z); its corrected diagnostic identified the blocked endpoint.

Newly discovered coverage gap: generators17/19 supply lake basins but did not
initialize their catalog. Integration with the existing finite-water bake/save
path is underway. Existing saves must not be populated or refilled on load.
Closure requires actual generated occupancy, fresh-process persistence, map
coverage, and inspected lake views. This does not reopen water flow or cosmetics.

Still open: broader seed/terrain admission, world visual acceptance, native/compute
work distribution, canonical storage recovery, large edit scaling, vegetation
streaming continuity and distant shadow substitutes, current exported packaging,
and representative populated travel/resource measurements. The rewrite remains
in progress; these checks do not certify a game-ready world.


### Generated basin integration

Generators17/19 now initialize finite-water definitions only for new/reset worlds;
existing canonical saves are not populated or refilled. Coastal terrain changes
basin heights, so native generation samples the actual floor and closed rim,
selects a contained level and seed, and rejects basins without sufficient depth.
This does not change the terrain field, existing saves, or static bucket behavior.
Seeds0/1/42/1703/9999/2147483647 pass deterministic native admission checks; invalid
records fail. Seed0 rejects its first shallow/open basin and retains three lakes.
This is explicit admission, not a claim that every seed includes a large lake.

The earlier lake_editor probe first exposed empty seed occupancy, then exceeded
its old30-second live-generation deadline (20261023T051705414397Z and
20261023T052133120024Z); neither is counted as passing. Offline generated_basin_review
passed (20261023T052309344861Z) and both retained lake images were inspected: a large
contained lake and a small shallow pond. World landscaping remains unaccepted.
Native fitting passes 20261023T052752487690Z.

Full seed0 connected-world creation and fresh-process verification now pass with
water included in the saved-content signature. Native publication reports ready:
integrated_rewrite_0_20261023, report d23449a0182a95ca1421ba06bb966d7b. Generation fills
water offline, and reopen verifies its cached state. A broader seed/shoreline matrix,
map preview of planned inland water, explicit generation-progress granularity and
populated travel performance remain open. Do not confuse these with flow work.

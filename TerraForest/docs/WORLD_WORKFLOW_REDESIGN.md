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

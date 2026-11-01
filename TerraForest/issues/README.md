# Visual issue tracker

One folder per problem: relevant images, current status, changes, remaining work
and a practical place to resume. Detailed evidence stays at its existing location.

| Issue | Status | Latest review / next investigation |
| --- | --- | --- |
| [Wearable clothing and trader outfit](woven-clothes/README.md) | Woven R1 installed / trader + trail source verified | Trader role outfit survives respawn; second CC0 pack supports paid crafting, swaps and fresh-process restore; both shown outfits approved and required in next combined build; all six remain craftable |
| [Authored door Open/Close](door-animation/README.md) | Installed / scoped checks | Authored GLB handle/latch and leaf motion; normal E, streamed visual ownership and mid-swing save/reopen pass in source/release/PCK; actual main executable checked, visual review pending |
| [Startup and browser latency](browser-responsiveness/README.md) | Improved-partial / installed, scoped checks | Background catalog/photo reads and bounded thumbnails; source first frame 1.75 → 1.24 s, filtering 45 → 2 ms with 299 saves; packaged browser/credits pass, export timing and player review pending |
| [Gameplay expansion](gameplay-expansion/README.md) | In progress / navigation installed, quest foundation source verified | Native bounded location ownership/state and normal generation/save/reopen pass; actual quest reset/trader interaction, lookout route and remaining expansions stay open |
| [Building expansion materials and joints](building-expansion/README.md) | E2 approved / production integration installed | Eight individual imagegen materials alongside retained optional older sets, shape/palette improvements and nine matched revisions; source/release/PCK, save/reopen and traversal checks pass; known older NPC planning and frame-pacing limits retained |
| [Trader and civic buildings](civic-buildings/README.md) | R1/E2 approved / production integration installed | Full trade, four basements, nine normal catalog choices and stock/inventory restore pass without review flags; source/PCK recipes and actual main executable checked; concurrent work preserved; broader frame pacing remains open |
| [Terrain crossing building blocks](terrain-building-contact/README.md) | Shared correction / enforced checks | Native shape-derived clearance, common datums and phase ordering, real footprint and exposed-surface publication gates; 30 debug/release + 64 catalog checks; human review and further recurrence coverage remain |
| [Unrequested mouse capture](mouse-capture/README.md) | Corrected / scoped checks | Click-to-play capture; loading and focus changes never reclaim the cursor; desktop review pending |
| [FPS / world overview](world-overview/README.md) | Partial / opt-in camera | Whole-world terrain/forest/boulder/static-prop/parked-vehicle coverage, archived exclusions and compact car LODs; prop paging/edit/reload checks integrated; transitions, dense costs, endurance and broader modules remain open |
| [Resource usage visibility](resource-usage/README.md) | Cached readings restored / bounded refresh | Size readings retained; opening uses saved/export/active-cache accounting, targeted native refresh has an 8 s budget; cold incomplete results stay explicit; initial counter cost remains reviewable |
| [Runtime performance](runtime-performance/README.md) | Improved-partial / save-priority fix source verified | Optional cache accounting now yields to async saves: same fixture completion over 20 s to 2.332 s; package check pending, 60 FPS pacing and historical large stalls remain open; cap and Quiet Mode retained |
| [Varied lakes and bridges](lakes-and-bridges/README.md) | Installed / scoped checks | Larger curved and two-lobed lakes; destructible timber crossings; actual-world player/NPC traversal and packaged reopen pass; user visual review remains |
| [Extended vegetation LOD](vegetation-lod/README.md) | Improved-partial / installed | Unchanged block/model paging no longer regenerates cover; zero near-owner misses in controlled 160 km/h repeats, density unchanged; outer coverage, frame pacing, physical vehicle/endurance and large-edit budgets remain open |
| [City buildings](city-buildings/README.md) | Approved designs / integration installed | Six exact approved designs on surveyed lots in larger recipes; populated-world player/NPC/vehicle routes, save/reopen, LOD and packed resources checked; site visuals and broader qualification remain |
| [Building geometry LOD](building-lod/README.md) | Installed / scoped checks | Default-on native geometry LOD plus world-wide distant block rendering, including never-visited archives; edits/reload and populated-world coverage checked; player review and denser-world endurance remain open |
| [Natural world-map presentation](natural-world-map/README.md) | Improved-partial / scoped checks | Cached water ready before first M; 1024² terrain, asphalt-first material ownership and unpainted shoulders; optional annotations; clustering/saves unchanged; finite zoom detail and shoulder geometry remain reviewable |
| [World generator UI and city layouts](world-generator/README.md) | Installed / scoped verification | Twelve distributed lakes, four-quadrant districts and longer connections; reproduced maximum inland fit corrected without relaxing cut/fill; more seeds and world-quality review remain open |
| [Building/POI terrain fit](site-terrain-fit/README.md) | Improved / scoped checks | Full-envelope/apron and driveway surveys, rectangular local pads; actual support/traversal checked; populated-site review pending |
| [Mouse capture / focus return](mouse-capture/README.md) | Fixed for reproduced cases / player review pending | No-click world entry and Alt+Tab return; actual Windows round trips pass; Esc/modal cursors and hidden-world isolation preserved |
| [Additional large house C1](large-house-c1/README.md) | Approved addition / integrated | New fitted neighborhoods and construction palette; native basement/slab preparation, multi-door publication and terrain traversal checked |
| [Dev Shapes catalog](developer-shapes/README.md) | Implemented / scoped checks | Searchable native-shape thumbnails, material grants and one-click placement setup; all 18 pieces tested; UI review pending |
| [Progressive harvesting](progressive-harvesting/README.md) | Implemented / scoped checks | Natural resources pay on damaging contacts with larger finishing rewards; native transactions and boulder save/reload verified; balance review pending |
| [Vegetation targeting flicker](vegetation-target-flicker/README.md) | Corrected / scoped checks | Removes running/turning preview lag and reach-edge disappearance; 70 packaged assertions pass; original-location review pending |
| [Player navigation and menus](player-navigation-menus/README.md) | Installed / scoped checks | ESC/inventory ×, quick quit, saved map markers/compass; 129 initial assertions and 48 inventory-follow-up assertions pass; user review pending |
| [Headlamp self-lighting](headlamp-self-lighting/README.md) | Corrected / installed, scoped checks | Excludes hands/tools in all three rendering modes; world beam unchanged; 305 packaged assertions pass, user review pending |
| [First-person world clipping](first-person-clipping/README.md) | Native-depth replacement / installed, scoped checks | Initial checkpoint comparison matched 13 scenes and 277 packaged assertions passed; later headlamp exclusion is intentional; user visual review pending |
| [Separate diagonal pickaxe study](pickaxe-crosscut/README.md) | Tip-first alternate retained / not default | User wants to keep this version for comparison but says its feel is still weaker; isolate the unsatisfying moment before another revision |
| [Discoverable material veins](material-veins/README.md) | Surface continuity corrected / scoped checks | Native pre-mesh material stems connect stones directly to buried veins; mining/persistence checked; appearance/balance await player review |
| [Player facing after vehicle exit](vehicle-exit-facing/README.md) | Fixed for reproduced behavior / scoped checks | Player faces current car front, input yaw stays synchronized; 110 focused/world checks pass, user review pending |
| [Reported fast-exit return](vehicle-fast-exit-return/README.md) | Unconfirmed / not reproduced | Four actual-world exits and seven resident-floor cases show no return; exact mod/build/speed and return destination needed |
| [ESC Player settings](esc-player-settings/README.md) | Implemented / scoped checks | Third-person and embedding switches move from Session into Player; session actions stay unchanged |
| [Vehicle sinks on exit](vehicle-exit-terrain/README.md) | Fixed for reproduced failure / scoped checks | Exit contact transition and fresh parking observations pass 18 repeated world exits; original-save user review pending |
| [Fly wheel initial hover](player-action-hover/README.md) | Fixed for reproduced case | Holding backtick selects the centred Fly action; release no longer needs a mouse wiggle |
| [Zombie ragdoll stability](zombie-ragdoll-stability/README.md) | Corrected at default 60 Hz / scoped checks | Ten stress fixtures, forest contact and four-direction walk-over pass; alternate 30 Hz physics and endurance remain unqualified |
| [Torch hand deformation](torch-hand-deformation/README.md) | Improved / partial | Rebuilt wrists and finger wrap at 60 Hz, locked runtime grip; revised hands await player review |
| [ESC UI priority](escape-ui-priority/README.md) | Fixed for current UI / scoped checks | Close active UI first; a fresh ESC opens pause only after returning to gameplay |
| [Backpack/toolbelt separation](inventory-backpack-separation/README.md) | Implemented / scoped checks | Container inventories show backpack slots only, not duplicated toolbelt contents |
| [World interaction hints](world-interaction-hints/README.md) | Improved / partial | E toggles container UI; harvest-only grass no longer intercepts stone/flower pickups |
| [Black terrain patches while mining](terrain-mining-dark-patches/README.md) | Improved / partial | 2026-10-26: recurrence gets user-approved faint cave visibility; latest images await review |
| [Pickaxe hits without excavation](pickaxe-no-op/README.md) | Fixed for reproduced case | 2026-10-26: saved-pose checks pass; reopen for another failing contact |
| [Terrain/road fit to building grid](terrain-road-grid-fit/README.md) | Improved / unresolved | Default improvement accepted; shoulder still fails |

This initial index is not the entire backlog. Other work remains in
[foundation status](../docs/WORLD_FOUNDATION_STATUS.md).

## Conventions

- Start from [TEMPLATE.md](TEMPLATE.md); keep summaries concise and folders stable.
- Embed a few relevant local `images/` files with captions: world/seed/location,
  build, settings, and baseline/improvement/rejected status. Mark unknowns.
- Prefer matching viewpoints and settings; label mismatches. Preserve original
  pixels and older iterations. Keep source paths and SHA-256 in `images/manifest.json`.
- Keep real images here, not temporary-file links. Do not commit private saves.
- Link existing technical logs, tests and code; do not relocate historical evidence.
- Update this index, issue summary and linked foundation status together.
- Keep user feedback separate from engineering checks. A scoped fix is not an
  all-world guarantee. Partial/unresolved stays open; a regression reopens its folder.
- Mark **Resolved** only with explicit scope, closing evidence and required visual
  approval. Preserve rejected trials and remaining limits instead of hiding them.

`.gdignore` and export exclusions keep the archive outside game resources.

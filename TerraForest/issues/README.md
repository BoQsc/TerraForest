# Visual issue tracker

One folder per problem: relevant images, current status, changes, remaining work
and a practical place to resume. Detailed evidence stays at its existing location.

| Issue | Status | Latest review / next investigation |
| --- | --- | --- |
| [Extended vegetation LOD](vegetation-lod/README.md) | Implemented / scoped checks | 576 m forest with native circular preload; cheaper distant fern/bush/twig meshes; near detail unchanged; long travel and player review remain |
| [City building proposals](city-buildings/README.md) | Review-ready / approval pending | Six native block designs: warehouse, police, medical, research, factory and apartments; isolated architecture/route checks, not yet added to generation |
| [Building geometry LOD](building-lod/README.md) | Installed / scoped checks | Default-on native cached LOD; 24-house moving-camera comparisons, all 18 shapes, edits and collision checked; streaming-boundary transitions and player review remain open |
| [Natural world-map presentation](natural-world-map/README.md) | Improved-partial / scoped checks | Cached water ready before first M; 1024² terrain, asphalt-first material ownership and unpainted shoulders; optional annotations; clustering/saves unchanged; finite zoom detail and shoulder geometry remain reviewable |
| [World generator UI and city layouts](world-generator/README.md) | Installed / scoped verification | Twelve distributed lakes, four-quadrant districts and longer connections; native routing/map/water allocation improved; largest inland fit and world-quality review remain open |
| [Building/POI terrain fit](site-terrain-fit/README.md) | Improved / scoped checks | Full-envelope/apron and driveway surveys, rectangular local pads; actual support/traversal checked; populated-site review pending |
| [Unrequested mouse capture](mouse-capture/README.md) | Corrected / scoped checks | Click-to-play capture; loading and focus changes never reclaim the cursor; desktop review pending |
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

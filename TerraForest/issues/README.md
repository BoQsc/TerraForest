# Visual issue tracker

One folder per problem: relevant images, current status, changes, remaining work
and a practical place to resume. Detailed evidence stays at its existing location.

| Issue | Status | Latest review / next investigation |
| --- | --- | --- |
| [ESC Player settings](esc-player-settings/README.md) | Implemented / scoped checks | Third-person and embedding switches move from Session into Player; session actions stay unchanged |
| [Vehicle sinks on exit](vehicle-exit-terrain/README.md) | Investigated / reproduced; fix pending | Exit restores player contact before its kinematic transition completes; stale parking readings can freeze the displaced car |
| [Fly wheel initial hover](player-action-hover/README.md) | Fixed for reproduced case | Holding backtick selects the centred Fly action; release no longer needs a mouse wiggle |
| [Zombie ragdoll stability](zombie-ragdoll-stability/README.md) | Improved / partial | Support edits and shared contact islands repaired; impact/stretch stress failures remain open |
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

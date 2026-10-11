# Development lake controls

2026-10-11. Escape > Water and the World tools HUD now share lake authoring controls:
carve at aim, inspect Ready/Baking/Failed state and elevation, retry failed bakes,
and remove water without carving terrain. Gameplay hides the page and action
callbacks enforce development mode. The existing compound catalog persists changes.

UI metadata is bounded by the existing sixteen-definition cap and refreshed on
catalog/publication events, coalesced into one deferred rebuild. No per-frame UI
loop, builder inspection or new GDScript simulation is added. Native baking stays
unchanged. Retrying rejects pending/ready work and retains definition and identity.

## Evidence and retained failure

- Six headless lifecycle checks pass with real native blocked-seed and valid bakes:
  state reporting, duplicate rejection, edit barrier, stable-ID retry, publication,
  and late completion after removal.
- Eight graphical functional checks pass: list, ready-state retry rejection,
  occupied seed, button removal/UI update, unchanged terrain revision, catalog
  restoration, republished stable IDs, and gameplay action rejection.
- The graphical suite is **not green**: the four-lake cold-start gate failed in
  both runs. Only two lakes were ready at 30 seconds. Final telemetry: lake 1 at
  3.699 s, lake 2 at 11.733 s; at the deadline one lake slice was outstanding,
  four worker jobs queued, worker status mesh. This identifies an open loading
  question, not its root cause. Restore later produced all four ready volumes.
- Final screenshot inspected at 1920x1080 fullscreen/cap60. Temporary-world save
  skips now say so instead of falsely showing Save failed. No frame-time claim.
- The first load failure was mixed GDScript indentation in the new metadata
  methods; corrected before the passing lifecycle/functional checks.

Tests use a temporary generated world; no user save is modified. Catalog restore
is exercised in-process, not fresh-process durability of the new UI path. Earlier
native/catalog persistence evidence remains separate. Human acceptance remains open.

Next bounded investigation: measure lake slice queue/execution timing and terrain
mesh occupancy around this cold-start gap, preserving edit priority and current
player loading. Do not repeat the same startup run without added attribution or a
specific scheduling change. Do not label water loading complete from these UI checks.

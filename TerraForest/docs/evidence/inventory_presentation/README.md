# Inventory presentation and direct crafting

2026-10-11. Main-scene presentation test: 15 checks, zero failures.
Reward/claim UI regression: see accompanying log for counts; zero failures.
Both ran fullscreen at 1920x1080 with the 60 FPS cap and no engine diagnostics.
These short UI checks do not qualify sustained frame time or thermal behavior.

`inventory_presentation.gd` sends actual mouse presses/releases to recipe cards,
checks exact one-batch cost/output, immediate availability refresh, rejected clicks
on disabled recipes, and safe stale-revision handling. It checks separate panel
bounds, empty slot transparency, active/selected distinction, empty-slot equipment,
and capture restoration when closing. Screenshots show the actual main scene.
`reward_claim_ui.gd` also preserves claim capacity/stale-state checks and crafting
notification checks after moving from the dropdown to direct recipe buttons.

Empty slots use 30% background opacity (filled slots 88%). Equipped slots have a
mint outline, a thicker lower edge and a stronger background, including equipped
empty slots. A selected inventory slot has a gold outline. Container grids reuse
the same empty and selected styles. StyleBoxes are allocated once per slot and
updated only when its appearance changes; no new frame loop or native hot path.

Crafting opens to the left with inventory. Four existing recipes are shown with
owned/required ingredients. One click requests one batch from the existing native
atomic exchange. Insufficient recipes are disabled, while output capacity and
revision are validated by the transaction before any input is consumed. Pending
materials still need claiming before use. No recipes, saves or costs were changed.

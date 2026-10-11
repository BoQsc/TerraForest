# Furnished storage interior — 2026-10-11

The main-world furnished cottage now includes table, chair, shelf and a separate
wooden chest. New placements and settlements composed from that palette entry
inherit the chest. Existing saved buildings are not modified. The legacy
`furnished_cottage()` helper remains the three-object variant; passing true adds
storage. This keeps old authored resources and fixtures explicit.

Gameplay prefab placement previously supplied furniture-only recipes, rejecting
chest and ladder attachments. Both synchronous and staged routes now use the
combined construction catalog. Chest and ladder recipes are shared with individual
placement, avoiding duplicated costs. The storage cottage costs its block materials
plus 25 wood for the four objects. Free-editor construction stays free.

The 32-check prefab test covers exact accounting, rejection without partial changes,
all four rotations, independent empty chest identities, staged paid placement and
structure snapshot restoration. It deposits into one native contents record before
placing further copies: construction does not copy that inventory into the new
chests. The original furniture-only transaction regression also passes.

The actual world passes eight checks at fullscreen 1920x1080 and cap60: selecting
the normal palette asset, paid placement, real physics picking/E interaction and
UI deposit inside the cottage. Screenshots show the separate shelf and chest.
These are short integration checks, not performance qualification: the screenshot
HUD reads 56 FPS and the fixture has no frame-time gate. Interior lighting remains
dark and final visual refinement is open. No native binary changes were required.

Reproduce with `tools/run_godot_check.py storage_prefab --headless --require STORAGE_PREFAB`
and `tools/run_godot_check.py storage_interior --require STORAGE_INTERIOR -- --gameplay-construction`.
This test does not exercise terrain grading or a multi-building settlement. General
editor block capture still captures blocks only, not placed model attachments;
this change supports authored combined prefab resources, not full-scene capture.

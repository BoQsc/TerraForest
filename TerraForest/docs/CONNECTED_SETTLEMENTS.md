# Connected settlement authoring

2026-10-09. The construction editor can now generate multiple building-lined
streets joined at both ends. This extends the existing frontage workflow into a
connected layout; automatic terrain-aware settlement placement, detailed city
content, navigation and scale qualification remain open.

## Use in the world

Select a building prefab such as Brick cottage and enter a name. Choose **Create
streets / settlement from prefabs**, set **Connected streets** to 2–8, and select
buildings per side, width, setback and seed. Optional source mixing uses the same
ordered building list and deterministic seed as the frontage tool. One street
retains the existing frontage behavior.

Create and save selects the new prefab. Aim at a suitable site, survey the selected
prefab, move outside its complete protection envelope, then prepare and place it
through the survey dialog. Preparation grades first and paves every street and
end connection before placement. Support and room-clearance checks still apply.
Completed road entrance pairs appear in the road catalog for later extensions.
F5 saves placed blocks, terrain and the road catalog through existing persistence.

## Architecture and bounds

`NativeBlockPrefab.compose_settlement(sources, lots_per_side, street_width, gap,
seed, streets)` performs native composition. Each row derives a deterministic seed,
normalizes building bases and maintains setback between adjacent rows. The two end
connections lie outside the complete building envelopes. Resources commit only
after native cell validation; rejection leaves earlier geometry/metadata intact.

Limits remain 262,144 total cells and local coordinates within ±4,095 for buildings.
Connected layouts use 2–8 streets, 1–64 buildings per side, even widths of 4–64 m,
and setbacks of 1–32 m. These are validation bounds, not a promise that every
combination fits or runs at 60 FPS. The existing low-priority authoring worker owns
source snapshots and saves the result; no per-building scene nodes are introduced.
Placed geometry remains editable block-world data.

Resource metadata `frontage_version=2` adds `street_lines` endpoint pairs and
`settlement_streets`; version-one frontages still work. The site planner validates
finite, axis-aligned roads, checks sampled foundation-column clearance, rotates the
whole layout and divides roads into bounded native grading commands. The combined
foundation/paving plan is still capped at 256 sections. All roads use one grade.

The road catalog adds the complete network atomically or leaves the prior catalog
unchanged at capacity. It uses the existing saved entrance format, capped at 256
roads. These physical connections are not a navigation/traffic graph. Multiplayer
replication is not added: generation produces ordinary authoritative block edits
and saved road records, without a separate transient runtime population.

## Verification and limits

Debug and release each pass 26 checks for deterministic geometry, exact connections,
transactional rejection, all four rotations, native asphalt and clearance samples,
resource reload, catalog persistence and all-or-nothing catalog capacity handling.
Existing checks pass for single-street paving (28), asynchronous frontage generation
(15), road continuation (16), and compound road persistence/connectors (27).

The actual 1920x1080 fullscreen editor test creates a two-street, four-cottage layout
through the real controls; surveys, prepares and places it; verifies obstruction
guards and vegetation clearance; and exercises all four road catalog entries.
The screenshots were inspected. This graphical fixture uses a temporary world;
its generated resource and catalog codec are tested separately for persistence,
and existing compound road persistence is retained as regression evidence.
The subsequent [combined world checkpoint](CONNECTED_WORLD_CHECKPOINT.md) now
passes fresh-process save/reopen with generated lakes and a static prop; broader
content and performance qualification remain open.

The graphical trace records p95 19.911 ms and a **2,002.161 ms maximum** frame interval,
with 1,975.924 ms inside the draw-to-post-draw interval. The cause is not established
by this fixture. Its screenshots, construction activity and first-use rendering
make it feature evidence only; it does not pass sustained-60-FPS qualification.
Preserve the outlier for the combined content performance checkpoint.

Two fixture setup errors were corrected: a CanvasLayer was incorrectly typed as
Control in the editor test, and the clean release project needed explicit extension
loading/report-directory setup. Initial failure logs are retained alongside passing
results. [Evidence and source/binary identity](evidence/connected_settlements/).

Run the short native check with `tools/test_native_release.py --addon structures
--test settlement_network --godot PATH`. The graphical route is
`tests/settlement_survey_editor.gd -- --connected-settlement-fixture` through Godot
at 1920x1080 fullscreen and a 60 FPS cap. Project code remains 0BSD; no dependency
or world-save format change was introduced.

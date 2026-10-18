# Northern common — 2026-10-18

Source world: northern_common_42_20261018, generator 13 / seed 42. The regional review
launcher creates a separate editable v9 copy. All earlier source/review saves and
player progress remain intact. The common lies on the west side of the northern
arterial, from approximately E1012..1020 / S234..278 in this seed. The supply chest
is at E1015 / S270.5. M tracks North neighborhood; follow its sidewalks to the common.

A two-metre path connects the existing sidewalks. Two small paved areas use two
shared tables, four chairs and a public wooden chest. The dense western planting
bed lies between them. The recipe adds 184 ordinary concrete block cells and seven
existing native model instances, with 35 existing collision proxy parts; no new
runtime process, per-prop script node, renderer or material. Furniture remains
static/destructible through existing interaction; sitting is not implemented here.
The public chest uses normal storage UI and generation-time supply distribution.

The new footprint is surveyed before surrounding road/lot earthworks. All seven
path beds belong to the northern master plan, ahead of structure publication. They
recess the existing surface by 0.1 m beneath the level paving to avoid coplanar
rendering. Seed 42 survey spans exactly 55 m: no raised construction pad or new broad
flattening. Both planting beds remain dense: 191 western / 211 eastern authored
instances, with normal native exclusion along the path edge (five fewer western
placements than the previous source).

Short native checks cover seven seeds, connected paving topology, building-footprint
separation and prop mesh support. The full master plan checks 3,688 foundation
samples with none unsupported. Direct combined native placement passes all four
rotations and exact snapshot restoration, including the declared 2 m-high attachment
envelope. Existing model collections/collision registration are used by that check.

Three staged bakes were rejected before publication: survey after edited ground,
path work after sidewalk blocks existed, and insufficient vertical bounds for the
attached models. Their logs are retained. The final generation and fresh-process
reopen pass, restoring exact blocks/models, supplies, road/fleet and vegetation
component signatures. The standard now explicitly requires short real-API placement
checks and preparation ordering before another complete bake.

A separate, uniquely cloned gameplay world walks all 13 waypoints using the normal
player controller (one initial staging teleport, no pose correction while walking),
from one sidewalk through both paved areas to the other sidewalk
and back to the chest. E opens the supply chest from the path. Normal storage UI
withdraws one wood, increasing carried stock by one and reducing chest stock by one.
An ordinary compound save then a fresh process restore the exact inventory bytes,
depleted storage bytes and on-foot position. E opens the same chest again. There is
no automatic replenishment or test-only chest/inventory mutation on this route.

Overview, ground, chest and reopened-chest images were inspected. The paving joins
both sidewalks, props rest on paving, the mixed planting remains, and the public
chest is accessible. This is a usable first outdoor common, not final landscape/art
or acceptance of the entire world. Existing surrounding streets, buildings and
vehicle bay are preserved; their full entry/driving suites were not repeated here.

The walking sample at fullscreen 1920x1080 / cap 60 has p95 16.828 ms and worst 17.755 ms.
Screenshot readback is outside those moving-frame samples. The collect/reopen
processes take 36.83 / 20.13 s including loading; full generation/reopen 121.57 / 21.50 s.
These bounded results do not establish steady 60 FPS, GPU headroom, old-laptop thermal
sustainability, long runs or town/city/multiplayer scale. Broader landscape continuity,
location character and overall world-quality review remain open.

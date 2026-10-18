# Player world map — 2026-10-18

Implemented in the normal saved world, using planted_neighborhood_42_20261018
(generator 13, seed 42). No save regeneration or user-save changes are required.
M opens/closes, Esc closes, and the actions menu also has a World map button.
Drag pans; wheel and buttons zoom; Find me and Whole world reset the view.
The mint arrow follows player position/heading at 5 Hz while open. Public destination
buttons/markers use existing destination tracking; secrets/undergrounds are omitted.

One 256-square RGBA survey texture is generated natively on an isolated TerrainCore
worker and cached with size/SHA validation. The map does not acquire the live terrain
worker or create world meshes. Base colours, contours, shading and basin water use
the immutable generator. Raster resolution is about 7.8 m per texel; this is a static
regional survey, not a live display of excavation, bucket edits or buildings. Four
base roads plus 22 actual saved street anchors are shown in the fixture. Authored
anchor widths are full widths; the first image review caught an erroneous doubling.

Native checks cover size bounds, identical seed output, changed-seed separation,
cold/cache equality and rebuilding then caching a correct-length corrupt file.
Cold native generation measured 5.52 ms, cold worker 7.48 ms. The saved-world cold
worker measured 8.95 ms; a fresh-process cache hit measured 1.07 ms. These are scoped
samples on the current RTX4050 laptop, not old-laptop thermal qualification.

Actual graphical input checks at fullscreen 1920x1080 / cap60 cover M/Esc, wheel,
left-drag, destination-button click, preserved terrain/inventory/equipment, blocked
movement, unchanged local streaming focus, reopening without another build and
preserved development selection/HUD. Overview and neighborhood screenshots were
inspected, including corrected label overlap/marker occlusion and road widths.
Marker-click, close-button and vehicle-driving paths exist but are not separately
qualified by these synthetic on-foot checks; overall human usability remains open.

Short frame samples (120 frames each; screenshot readback excluded):

| Stage | p95 frame ms | worst ms | p95 GPU ms |
|---|---:|---:|---:|
| Closed before | 17.483 | 17.698 | 6.563 |
| Map open | 17.513 | 17.795 | 6.570 |
| Closed after | 16.815 | 16.968 | 7.084 |

These support a small measured map cost in this stationary scene. They do not
establish steady 60 FPS, long-run headroom, traversal or thermal performance.
An intermediate fixture lost OS focus while shell polling; its M-open failure is
retained. Synthetic input now explicitly assigns the host focus flag, as other
world fixtures do. Native input/presentation still runs normally.

The broader unified-tools test initially failed five assertions. Diagnostic traces
showed fixture assumptions that no longer match gameplay: 5000-unit supply grants
fill supposedly empty drag targets, re-equipping a pickaxe may occupy belt slot 9,
held block materials enable paid placement, developer exit restores actual equipment,
and bare hands use durability-based terrain attacks. The fixture now explicitly
prepares empty targets and checks these current behaviors. It passes real chest
withdrawal/deposit/rearrangement/Shift-drag, belt movement, M-map return, tilde/flight/
headlamp isolation, Objects/Building menus, real pickaxe mining and bare-hand damage.
No runtime gameplay changes were made to obtain those updated UI-test results.
The older player-HUD/geometry fixtures were migrated away from M object editing;
those whole suites were not rerun in this map pass.

Existing world-building, sustained-performance, public-space and vehicle-turning
requirements remain open. This is the first useful map milestone, not completion
of the project foundation or overall world-quality acceptance.

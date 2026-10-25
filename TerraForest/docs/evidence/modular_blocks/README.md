# Native modular blocks — 2026-10-25

## Delivered scope

Six new individual one-metre-grid block types: thin panel (ID 9), frame corner
(10), quarter arch (11), roof ridge (12), outer roof corner (13), inner roof
corner (14). These are selected mathematical recipes reimplemented in native C++,
not the upstream GDScript world, imported continuous frame meshes, or all 224
source variants. The initial source/licence assessment remains in
`../block_shapes_addon/README.md`. The native implementation remains under the
repository's existing licence; no new runtime third-party dependency is introduced.

The frame trim and quarter curve form multi-cell assemblies. A four-cell archway
clears a 1.8 m player capsule. Each cell independently stores shape, orientation,
material and damage identity and can be removed without removing its neighbors.
Existing houses, prefab resources, generation rules and trusted road plates are
unchanged. No house is redesigned or approved by these tests.

## Player controls

Equip Brick, Wood, Concrete or Metal. Hold **Alt**, choose the shape in the quick
tool panel, then release Alt and right-click to place. **R** cycles yaw;
**Shift+R** cycles mounting direction. The rotation dropdown also exposes all 24
axis-aligned orientations. Normal tool strikes damage and destroy the selected
block at animation contact, using existing material health and tool wear.
Development building mode retains free placement and left-click removal.

Both quick and detailed controls use the same names/IDs. The old main-world
selector incorrectly rejected every shape beyond six despite showing eight;
that gate now accepts the complete supported catalogue. Quick controls now refresh
after selection/hotkeys instead of showing stale Cube/rotation values.

## Native implementation

- Immutable native templates share render faces and convex-part definitions.
  The quarter curve uses twelve facets with smooth radial normals and hard flat
  caps. No JSON geometry parsing or per-frame GDScript mesh generation is added.
- The existing worker creates chunk render/collision meshes. Exact clipping removes
  covered boundary polygons from both neighbors, including old/new shape seams;
  empty portions of arches/frames remain empty. Unchanged indexed triangles stay
  shared and unused vertices are compacted, rather than tripling legacy mesh data.
- Existing low-byte words are unchanged. New words use the high marker and stable
  shape IDs within the existing 16-bit cell payload. Material bits remain unchanged.
  The encoder validates IDs/orientations; prefab yaw preserves the mounting group.
- Legacy-only saves still produce TFBL v1. Extended cells use TFBL v2 with the same
  16-bit RLE record layout and checksum. New readers accept both; old readers reject
  v2. Region paging, history and compound structures storage retain exact words.
- Authoritative picking, physical collision and exported water-solid hulls agree
  with the same shape geometry. Map-column heights account for rotated new geometry.
  Native cell ownership is never replaced with a single architecture model.

## Verification

| Check | Result |
| --- | --- |
| Final debug component suite | 1,306 checks, zero failures |
| Isolated release-DLL component suite | 1,306 checks, zero failures |
| Actual source-game placement/destruction | 97 checks, zero failures |
| Exported-game placement/destruction | 97 checks, zero failures |
| Separate-process exported-save restoration | Pass, exact binary bytes |
| Seven legacy mesh fixtures | Exact original geometry/normal/UV/material/index hashes |
| Broad structures suite | 294 checks, zero failures |
| Signed region paging, trusted paving, construction inventory | Pass |
| Native worker and legacy solid-query regressions | Pass |
| Pack export/startup and both copied DLL hashes | Pass |

The component checks cover all 144 new shape/orientation combinations, legacy
words/materials, invalid-word atomicity, outward winding, each triangle's solid
and empty sides, cached previews, physics-versus-authored ray agreement, binary
roundtrip and region paging, all prefab yaw compositions, mixed/negative chunk
seams, shared arch-cap culling, player-sized arch clearance, and independent
removal/undo/redo. All new pieces stay within their cell.

The real-game checks use actual ALT controls, R/Shift+R inputs and right-click
placement, debit exactly six wood units, then use real animated axe strikes to
destroy all six shapes independently. They check hit targeting, material health,
wear, neighboring support survival and compound storage restoration. The final
PCK run uses packed game resources and copied native DLLs; only the test/animation
driver is external. It creates a temporary world and explicitly skips player-save
writes. A second engine process restores its saved block bytes.

`pack/quarter_arch.png` and `pack/placed_shapes.png` were inspected. They show
temporary airborne test supports above the canopy, not a generated location or
proposed house. The translucent arch is the live placement ghost; the opaque wood
piece is already placed. The first diagnostic image was obstructed by foliage;
the final fixture raises only its test supports for a clear view.

Small repeat-edit measurement on this i5-12450H/RTX 4050 machine: 64 mixed modular
cells, eight alternating single-cell edits with explicit flush and collision.
Final release measured **2.293–2.553 ms**, debug **2.576–3.723 ms**. These include
worker waiting and are not FPS or a dense-city/long-duration frame-time guarantee.
No native/GPU rewrite claim is inferred from the HUD's 60 FPS display.

## Failures kept visible

The previous 18 broad structures failures came from three fixtures treating the
already-supported round-column word **7** as invalid. Those three inputs now use
reserved **256**, retaining their rejection/atomicity assertions. The component
suite separately verifies every valid legacy word. No production validation was
weakened to make the suite pass.

The standalone `construction_palette_layout` fixture still fails its fixed
900-pixel boundary assertion, including with the original palette and original
test from commit `54d9a845`. Both baseline and final failures are retained under
`layout/`. This is separate from the tested in-game ALT panel; detailed controls
are docked inside the existing scrollable workspace. A standalone layout repair
remains open rather than being hidden or counted as a pass. The first candidate's
extra hint line was removed; rotation help is a tooltip and quick-panel hint.

## Remaining scope

No complete architecture meshes, arbitrary diagonal block rotations, monolithic
frames, new houses or automatic existing-world conversion. Full shallow hollow
roof phase/transition kits and other upstream variants need separate grid-safe
recipes and tests. Dense-city/endurance and new-shape-specific NPC routes are not
qualified by this component/player pass. Existing native physics/solid interfaces
are preserved; this is not a navigation-system rewrite. Each proposed house still
requires explicit user approval before adoption.

`manifest.json` records source/test/library and retained-evidence hashes. The
`run.json` files retain executed commands, results and test provenance. Reproduce
source checks with `tools/run_godot_check.py modular_blocks --headless --require
"MODULAR_BLOCKS checks="`, or `modular_blocks_world --require
"MODULAR_BLOCKS_WORLD checks="` using the local Godot editor. Use a temporary world
and isolated report/cache paths; do not aim these fixtures at a player save.

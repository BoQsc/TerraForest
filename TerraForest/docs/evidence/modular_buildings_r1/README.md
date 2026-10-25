# Whole-building modular proposals R1

## Status and boundaries

**Engineering demonstration passes. Both architectural proposals await individual
user approval. No existing house or generation default is replaced.**

These are alternatives to `furniture_catalog.enclosed_cottage()` and
`workshop_catalog.village_shop()`, not unrelated showcase buildings. The originals
are instantiated unchanged next to the candidates. Cameras, lighting and materials
match on both sides. Ground is an isolated neutral review backdrop, not a newly
graded settlement. No player save is read or written by the viewer.

Use `python tools/review_modular_buildings.py` for the one-window guided review.
The guided tour visits exterior, detail and interior for each building over 45
seconds. A manual view selection cancels it. The viewer loads baked native prefab
resources; recipe loops are retained only for reproducible offline authoring.

## What changed

| Candidate | Block-based changes | Retained |
| --- | --- | --- |
| Cottage A R1 | Segmented porch arch, supported pedestals, flush timber gables, thin ceiling, pointed ridge, side roof overhang | Main brick walls, usable center stairs, door/windows, furniture and chest |
| Village Shop B R1 | Four-sided hipped roof with separate hip corners and ridge, ceiling, internal stores arch | Main footprint/walls, entrance, counters, windows, shelves and chests |

Cottage A has 556 cells; Shop B has 963. Both use two separate quarter-arch blocks
and a separate top panel per arch, supported by independently addressable parts.
No building part is stretched outside its cell; no complete frame/arch model is
introduced. These examples intentionally use the shapes that serve each design,
not every new shape for the sake of demonstrating a catalogue.

The existing door/window/furniture/storage object attachments are preserved
exactly. Every newly added piece of building fabric is native grid construction.
The apparent continuous roof/ceiling surfaces are chunk batching, not single
authoritative meshes. The removal action leaves a one-cell opening and preserves
the rest of the building. This is local removal, not structural collapse simulation.

## Retained evidence

- `images/cottage_exterior.png`, `cottage_detail.png`, `cottage_interior.png`:
  unchanged cottage beside its R1 proposal.
- `images/shop_exterior.png`, `shop_detail.png`, `shop_interior.png`:
  unchanged store beside its R1 proposal.
- `images/cottage_removed.png`, `shop_removed.png`: one quarter-arch block removed,
  with the adjacent blocks remaining present.
- `graphical/`: final commands, engine/native hashes, logs and 47 passing checks.
- `restore/`: a fresh process restores the saved compound data after a local edit;
  three passing checks and exact byte comparison.
- `result.json`, `review.tfbs`: final native statistics and compound review data.
- `initial/`: first cottage exterior/detail renders and earlier run provenance.
- `failed_support_probe/`: the retained support-probe failure and its provenance.
- `manifest.json`: retained evidence, source, original-catalogue and asset hashes.

All eight final images were inspected. Earlier images showed a stepped/recessed
cottage verge and side upright bases hovering over sloping treads. The proposal
was revised to a flush gable edge and level concrete end pedestals while retaining
the center stairs. Those initial images are not the final R1 proposal.

The final checks cover atomic publication of four native prefabs plus attached
models, exact original/attachment preservation, baked-authoring equivalence,
review-only flags, GUI view selection, guided-tour cancellation, one-cell removal
and exact restoration, pedestal support, working retained doors, native player
walking from ground up steps through entrances and aisles and back down, and
compound storage. The final scene has 2,804 cells, 16 mesh/collision chunks and
9,430 triangles. Counts are not a frame-time or dense-city performance guarantee.

The first support probe fired a front-face picking ray from inside the continuous
upright/pedestal solid. Such rays intentionally reject internal starts, so it was
not a valid contact test. The corrected test checks solid samples immediately
above/below each base along its depth and verifies the underlying full concrete
cells; actual ascent/descent also passes. Production picking was not changed.

## Still pending

Each candidate requires explicit user approval. Neither is registered in the
normal prefab palette, a generator recipe or an existing save; `reviews/*` is
excluded from game exports. This commit preserves proposals for review only.

After approval, verify changed exterior envelopes against real lots, neighboring
paths and vegetation, terrain fit, full-game save/reload, interaction/placement
and representative populated-world travel/performance. Existing main-game tool
damage for modular blocks was checked in the preceding native integration; this
viewer demonstrates direct cell removal, not a new combat or health implementation.
NPC routes, long-duration budgets, hollow shallow-roof phase kits and structural
collapse are not qualified by these tests. Approval must not silently waive them.

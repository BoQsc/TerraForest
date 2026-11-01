# Native building expansion format

New original implementation: 0BSD. Existing source notices remain in force.

## Cell identity

Cells remain unsigned 16-bit values. Zero means empty. All pre-expansion words
retain their exact representation. Existing 1–8 shapes have four yaw rotations;
modular shapes have 24 mounting orientations. The integrated catalog has 36 shapes.

Bit 14 marks a styled word. Removing that marker and closing its gap leaves a
15-bit payload: bits 0–2 appearance (0–7), bits 3–4 structural material (0–3),
remaining bits a pose ordinal. Ordinals 0–31 represent shapes 1–8 × four yaw
orientations; ordinals 32 onward represent shapes 9–36 × 24 mounts. Ordinals
outside the supported catalog reject. `block_word.hpp` owns all encoding and
decoding; consumers must not manually extract the old material/rotation bits.

Appearance never changes inventory cost, damage family or salvage identity.
Prefab rotation preserves it. Appearance indices select E2 aged brick, plaster,
limestone, timber, slate, zinc, clay and stone trim. E1 was an unreleased rejected
prototype of these appearance slots: its saved review clone can render with the
new art in this development build. This is **not** a compatibility promise for
E1 draft styling. The approved R1 worlds contain legacy words and remain unchanged.

TFBL snapshot version 3 is required whenever any styled word is present. Pure
legacy worlds keep version 1/2. Readers validate version, cell word and checksum
before publishing changes; a valid-checksum version downgrade containing styled
words rejects atomically. Region paging and whole-world archives share validation.

## Rendering and collision

The shared shader keeps four legacy layers and adds a lazy eight-layer appearance
array. UV2.x carries render layer 0–11, with +16 for the existing plate-edge cue.
LOD/horizon copies retain UVs and layer identity. There are no per-cell materials
or extra per-cell draw calls. A roof shell or closed gable's upward face uses its selected
appearance and its end/underside uses its structural family's finish; both remain
in one mesh and one authoritative cell.

Shapes 19–27 are 1:2 roof phases/ridge/hip/valley parts; 28–31 are cornice/coping;
32–36 are closed shallow and pitched gable parts. The native clipped polyhedron
provides both triangles and convex hulls. Components remain within their unit
cell; multi-cell roofs and trims are authored assemblies. IDs 26/27 have only
fixture evidence so far and are not proposed for default building adoption.

`building_uv.hpp` maps styled vertical faces downward and roof texture rows
across local slope, with +V downhill. Modular mapping happens before rotation,
so it follows tipped and rolled parts. The physical repeat is the projected
integer-grid metre, preserving phase across adjacent cells/chunks.

## Validation and review

`tests/building_expansion.gd` exhaustively checks all 65,536 words, legacy byte
identity, all new shape mounts against exact solidity, equivalent gable volume,
shared gable-face batches, published roof UV gradients, crafting material counts,
snapshot downgrade rejection, region paging, prefab yaw, one-cell undo and joined
roof surfaces without collision slivers across chunk boundaries.
`tools/check_building_standards.py` runs it against debug and isolated release
libraries and enforces terrain/contact and material checks before export.

None of these gates approves the artwork or a building revision. The material
standard and populated-world review remain separate requirements. New prefabs
are exposed only through `--building-expansion-review`; ordinary generation
continues to use its approved resources. No automatic save migration is added.

# Binary world format and inspector

The existing native root format is `TFWORLD1`, version 1. It is portable binary
data with explicit little-endian fields, not a memory dump of C++ structs and
not JSON. Changing a compiler's ABI does not change these stored field layouts.
The native implementation is `addons/world_runtime/native/world_archive.cpp`.

## Root layout

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 8 | ASCII `TFWORLD1` |
| 8 | 4 | Unsigned version, currently 1 |
| 12 | 4 | Unsigned section count, 1–128 |
| 16 | 32 | SHA-256 of bytes 8–15 followed by bytes 48–end |
| 48 | variable | Sorted section records |

Each section record is `u32 name_length`, `u32 payload_length`, ASCII name and
payload bytes. Names are 1–48 lowercase ASCII letters, digits or underscores,
strictly increasing and unique. A `terrain` section is required. The root is
capped at 256 MiB; each non-terrain section is capped at 64 MiB. Trailing bytes,
unsupported versions, bad bounds, names or hashes fail validation.

Each component owns its own binary version and semantic validator. Many contain
fixed numeric records and packed fields. Some existing component envelopes and
the placement-plan cache still contain Godot Variant serialization; eliminating
those is explicit remaining work in [NATIVE_GENERATION.md](NATIVE_GENERATION.md).
A binary outer container is not proof of an optimal internal representation.

Large stores are referenced through native sections and companion paths such as
`<slot>.trw.regions`, `.models`, `.water`, `.terrain` and `.baselines`. Keep their
exact layout, identities and dependencies. The inspector does not claim that
checking a root checksum validates every companion store or physical world rule.

## Compact first generation

Fresh generated worlds can store the complete native TFSB structure/model
snapshot directly in the compound root. This preserves the existing canonical
record encoding and avoids creating thousands of small per-model store files
before first play. Structure/model records remain native binary records.
A subsequent edited save can publish regional references, retaining the compact
root as the ordinary backup. Existing regional saves remain supported.

The native inspector distinguishes complete resident records from regional
references and validates either form before publication. Map certificates use
the exact restored block/model snapshot hashes for resident records. Terrain,
water and location-baseline companions still belong to the portable world; a
small root is not a self-contained substitute for those companions.

## Inspector commands

The inhabited-island recipe uses `RCP1` version 9: eleven little-endian u32 words
(44 bytes), consisting of magic, version, biome, settlements, districts, network,
trails, road grid, material veins, introduction and profile. Profile 2 requires
seven settlement groups, one district and introduction 0. Its immutable terrain
generator is 36. Existing Metropolis profile 1 remains version 8; older recipes
keep their versions. The inspector can decode/compile both without changing
their byte layouts. A recipe remains input to generation; editing a save's
recipe does not regenerate its physical content.

Run from the project directory, supplying an explicit root file:

```text
python tools/world_inspector.py inspect path/to/World.trw
python tools/world_inspector.py inspect path/to/World.trw --full
python tools/world_inspector.py verify path/to/World.trw
python tools/world_inspector.py diff path/to/Before.trw path/to/After.trw
python tools/world_inspector.py extract path/to/World.trw --section world_recipe_v1 --output recipe.bin
python tools/world_inspector.py native-check path/to/World.trw
```

`inspect`/`verify` check the full root hash and structure, plus the known recipe
and generated-region schemas. Every other section is explicitly marked as not
semantically validated. Full verification of an entire saved world still requires
the engine's native component/companion validation and fresh restore.

`native-check` launches one headless source-engine process, using the same native
verifier as ordinary world publication. It checks current regional terrain,
resident or regional structure/model records, water and location-baseline references, recipe and world identity.
Close that world first: the native verifier requires its save lease. It does not
create a new world or copy the save. The root hash must remain unchanged. A
2 MiB storage admission covers its receipt, logs and JSON under
`reports/world_inspector/`; completed and failed small evidence stays with the
receipt. Use `--godot PATH` to select another compatible engine. This is not a
complete semantic check of optional gameplay components or historical inline roots.

`--full` exposes recipe fields and complete place/road metadata as readable JSON.
The default summarizes the region to keep output small. Offsets, byte lengths
and SHA-256 values let other inspection tools locate and compare native sections.
`extract` and JSON export refuse to overwrite an existing output file.

## Restricted JSON editing

For new-world authoring, export a recipe, edit its numeric options, and compile:

```text
python tools/world_inspector.py export-recipe path/to/World.trw --output recipe.json
python tools/world_inspector.py compile-recipe recipe.json --output recipe.bin
```

Compilation validates the exact supported option set and emits the existing
28–44 byte native recipe plus its `--world-recipe=...` launch argument. It rejects
unknown keys, non-integer flags and invalid combinations. Generation consumes
these compiled bytes through the ordinary recipe path. No existing world is
regenerated or physically changed by these commands.

For existing-world place labels:

```text
python tools/world_inspector.py export-labels path/to/World.trw --output labels.json
python tools/world_inspector.py apply-labels path/to/World.trw labels.json
```

Edit only `title` and `detail` in the exported document. Titles allow 1–96 and
details 1–192 printable ASCII characters, matching the native map schema. The
complete ID set and source SHA-256 must match. Missing/extra fields, duplicate IDs,
stale files, changed positions, recipe options or generator IDs are rejected.
Seed/profile changes would require regenerating physical content and are not
metadata editing operations.

On Windows, applying labels acquires the same exclusive root `.lock` used by
native saving. It writes a unique adjacent backup and pending root, flushes and
verifies their bytes, then replaces the root with a write-through rename.
Companion files and every other section are unchanged. Failed publication retains
its recovery files. The command prints the exact backup path and before/after
hashes. A no-op edit writes nothing. Close the world before editing; the active
save lease prevents concurrent publication.

The inspector only allocates explicitly requested exports or an explicit label
edit's backup/pending roots (each at most 256 MiB). These operator-owned backups
are not disposable test evidence and are never automatically deleted. Developer
checks must pass storage admission before producing their receipt-owned fixtures;
the interoperability fixtures are synthetic and together remain below 128 KiB.

## Validation

`tools/test_world_inspector.py` covers envelope corruption/truncation/bounds,
legacy/current recipes, unsupported metadata, exact roundtrips, restricted edits,
stale fingerprints and untouched opaque sections. `tests/world_inspector.gd`
checks the same original/edited fixture with native encoders and validators.
These prove the documented schema boundary; they do not validate arbitrary
unknown components or accept an entire generated world's visual/performance quality.

# Structures in the compound world save

The terrain scene now registers one native structures bundle alongside water. The bundle contains the independent block world and all configured model collections with stable IDs, asset keys and transforms. Its immutable native validator runs on the terrain worker before terrain deserialization. Known corrupt components and unresolved assets cannot partially restore the scene or overwrite the canonical file on shutdown.

Reproduction:

```text
python tools/validate.py --test structure_persistence --godot PATH
python tools/test_native_release.py --addon structures --test structure_persistence --godot PATH
python tools/validate.py --test structure_world --gpu --godot PATH
```

The persistence suite passes **59 checks in debug and release** using real native terrain, water registration, block data, two/three mesh assets and disk publication. It checks ordinary saves, independent structure edits on shutdown, reload queued before shutdown, asset registry extension, missing asset rejection, malformed nested payloads inside a valid outer archive, failure atomicity, immutable schema, returned-byte isolation, transient capture-error recovery, stale capture ordering, and the new bounded component size. Existing archive, water persistence, structures and static placement suites also pass.

The integrated graphical suite passes **15 checks**: normal scene loading, real terrain collision, building publication, B-mode selection, actual block placement/removal through picking, unchanged terrain density, existing player standing on building collision, static placement ownership, bundled capture and 1920×1080 fullscreen measurement. Evidence is under `docs/evidence/structure_persistence`.

Visual review found that forest instances overlap the test building and obscure it. The screenshot records this unresolved issue; passing collision/persistence checks is not evidence of finished world composition. Building-footprint vegetation exclusion is required. Static-model collision, an asset placement UI, native player replacement, explicit structure collision readiness during loading/high-speed travel, region storage/eviction, bake caching, city generation and multiplayer remain unfinished.

This work does not establish large-world save latency or long-run performance. Capture/restore still materializes complete snapshots; cached captures return defensive byte copies. Bounded section sizes avoid unlimited archive allocation, but the collection registry is not yet a global scene memory budget. The standalone architectural showcase retains its separate block-only demonstration save; the terrain scene uses the compound archive.

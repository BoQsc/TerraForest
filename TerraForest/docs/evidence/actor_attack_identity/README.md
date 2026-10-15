# Actor attack identity, 2026-10-15

Supports M3 interacting entities. World attacks previously resolved a hit actor's
body by searching a 1 cm sphere in the entity store, with a 64-record visit cap.
Coincident records could make the query incomplete or resolve a different record.
The actual-world regression reproduces a missing target with 80 other stationary
records at the active actor's position; `before.log` retains the failure.

`NativeEntityActor.entity_handle(store)` now returns its bound handle directly,
only while attached and still valid in the supplied owning store. Existing
generation validation rejects despawned/reused handles. WorldAttack uses that
handle and its persistent identity instead of a spatial search. This adds no
per-frame work, bodies or save-format changes. Update both native DLLs together
with the script adapter.

Evidence:

- `world.log`: actual main-world physics hit resolves the correct actor; seven
  normal damage applications retire it and leave all 80 other records intact.
  Temporary world, fullscreen 1920x1080, 60 FPS cap. Initial development-mode
  fixture is switched to gameplay before equipping the pickaxe. No saves changed.
- `native_debug.log` / `native_release.log`: identity, foreign/null authority,
  despawn, slot reuse and explicit rebind; existing walking/wall/readiness checks
  still pass with 100,000 dormant records. Both binaries rebuilt using pinned
  Zig and prebuilt godot-cpp; SDK sources were not rebuilt.

The coincident records deliberately have only one active collision body. This
checks identity correctness, not crowd avoidance, crowd rendering or population
performance. Settlement navigation, regional routing and broader entity coverage
remain separate gates. Water was not changed.

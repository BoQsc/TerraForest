# Aimed dropped-item recovery — 2026-10-15

The shared world prompt now names dropped tools, ores and other catalog items.
NativeEntityStore.query_segment intersects 0.32 m spherical pickup proxies in
local spatial cells, selecting the nearest entry and breaking ties by persistent
identity. Queries reject nonfinite inputs, degenerate segments, segments over
8 m, radius over 1 m and invalid budgets. Exhaustion returns no partial target.

The scene adapter caps the whole catalog search at 1,024 visited candidates per
10 Hz prompt update. It runs no per-record GDScript loop and checks center
occlusion for only the winning pickup. Ground cover and loose pickups compete
by first-hit distance; doors/chests retain their interaction priority. E repeats
selection, then transfers through the existing native inventory/container path.
No per-pickup nodes or active rigid bodies were added. Nearby collection remains
a keypress-only fallback. Its obstruction mask now includes vehicles as well as
terrain and structures. Collection also rejects reentrant transfer attempts.

Both debug/release world_runtime DLLs rebuilt using Zig/prebuilt godot-cpp;
zero SDK sources compiled. Targeted checks passed:

- entity_segment: nearest/reverse/inside/miss/clipped rays, cross-cell picking,
  stable ties, removal, invalid input and candidate exhaustion. 3,000 distant
  records leave the local query visiting one candidate.
- pickup_interaction_hint: actual temporary world, dropped pickaxe recovery
  with wear 7 intact, iron ore identity/quantity, prompt clearing, vehicle-layer
  obstruction of both aimed and fallback recovery.
- ground_interaction_hint and building_interaction_hint graphical regressions.
- bundle_pickups: existing catalog rendering/transfer/compound restoration checks.

Graphical checks use 1920x1080 fullscreen and a 60 FPS cap. No sustained timing,
thermal or large-city qualification is claimed. The spherical proxy is advisory
interaction geometry, not a triangle-exact model selection. Crowded local cells
can exceed the explicit candidate budget and suppress aimed selection. The
initial world run failed a GDScript type inference error; corrected before the
passing run. Human saves were untouched.

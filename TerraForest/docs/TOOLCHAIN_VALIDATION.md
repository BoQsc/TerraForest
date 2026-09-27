# Native toolchain and fullscreen validation — 2026-09-27

Godot 4.7.2-stable (steam), Windows x86-64, Forward+, NVIDIA GeForce GTX 1060 with Max-Q Design.
The current scene renders at 1920×1080, exclusive fullscreen, 100% 3D resolution.
Historical results in VALIDATION.md used 1600×900 and are a separate run.

## Completed checks

- Zig 0.16.0 and the supplied API 4.7 prebuilt godot-cpp archive downloaded and verified against pinned SHA-256 digests.
- Debug and release extension DLLs built and loaded in Godot. No godot-cpp source was compiled locally.
- Debug native entity suite: 18 passing checks. Release DLL in a clean project: 19 passing checks.
- Second builds of both variants compiled zero sources and skipped linking.
- Fullscreen capture verified 1920×1080 pixels.
- Full rendered terrain/forest scene: 15 passing checks, including excavation, updated collision and four travel cycles.
- Resource pack exported and started with all three required Windows native DLLs beside the pack.

## Measured sample

1800 uncapped frame samples during the warmed camera view: median 7.506 ms,
p95 8.905 ms, p99 9.997 ms, maximum 34.167 ms.
This is a scene sample, not worst-case travel performance, a speedup comparison or multi-hour endurance evidence.

The native entity test runs 100,000 entities for 240 kinematic ticks and outputs a bulk transform buffer.
It does not measure rendered entity population, collision, vehicles or multiplayer capacity.
The first Zig link populated compiler runtime caches; later builds reuse them. These caches are separate from the downloaded godot-cpp libraries.

## Remaining scope

The inherited terrain binary was retained. Existing GDScript streaming and vegetation scheduling have not yet been migrated to C++.
Volumetric water, new road/building/city systems, inventory, authoritative multiplayer and vehicles remain unimplemented.
See WORLD_SYSTEMS_DESIGN.md for the expansion contract and NATIVE_DEVELOPMENT.md for reproducible builds.
Matching standalone Godot export templates are still needed for a standalone executable release.

Raw reports and current captures are in evidence/native_1080p/.

# Release qualification

The packaged revision is a development release. Current evidence is recorded in VALIDATION.md; these are the next gates before describing it as a production-ready general-purpose world system.

- Run multi-hour traversal and edit/undo-like workloads on target hardware; log process working set/private bytes and driver VRAM, not only Godot static memory.
- Exercise worst-case cave construction, large contiguous edited regions, native page limits, repeated saves, interrupted writes and disk-full recovery.
- Measure warm and cold startup, continuous travel, fast flight, teleports, large brush publication and collision creation separately. Record p50/p95/p99 wall and GPU times; compare both original projects under matched scenes before claiming a speedup.
- Validate Linux on hardware. The Linux library is supplied unchanged; Windows runtime success does not establish Linux support quality.
- Run supported Godot renderer/version combinations and check LOD fades, foliage alpha, wind/shadows, lighting under roofs and seams between cached/edited terrain.
- Decide production policies for edited-surface regrowth, multiple species, tree collisions, network authority and origin shifting. Current APIs document their constraints.
- Install matching export templates externally when a standalone executable is needed. Verify the executable and native libraries in a clean extraction on a second machine.
- Review texture/spruce provenance notices for the intended redistribution and include the appropriate licenses in public releases.

No cloud upload, repository publication, or claim of certification is part of this local build.

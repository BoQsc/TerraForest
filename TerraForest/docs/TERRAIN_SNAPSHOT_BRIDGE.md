# Opt-in Godot snapshot geometry API

TerrainCore now exposes three experimental methods in both extension variants:

- `experimental_snapshot_submit(x, z, size, token, revision)` captures a region
  only when the requested revision matches the authoritative world. Width is
  limited to 1–32 m. A lazily created native worker owns two outstanding slots,
  a 3 MiB snapshot heap budget and a 32 MiB mesh heap budget.
- `experimental_snapshot_poll()` consumes available results as dictionaries with
  token, epoch, revision, stale flag, numeric MeshStatus, positions and indices.
  Positions are packed float32 XYZ bytes; indices are packed uint32 bytes.
  Stale or failed results have no geometry payload.
- `experimental_snapshot_stop()` closes admission and joins the worker, retaining
  completions for polling. This instance cannot restart its stopped worker.

Capture and poll hold the existing authoritative-world mutex. Mesh computation
runs outside it. Edit revisions invalidate old results. A separate snapshot epoch
also invalidates cancellation, reset and load, because reset/load can reuse a
revision number. Cancellation is checked again after output encoding because
command 12 deliberately bypasses the world mutex. Callers still need their own
final publication freshness checks once the method returns.

Run `python tools/probe_terrain_snapshot_bridge.py --godot <executable>`.
All 15 checks pass in the release extension: bounded admission, indexed geometry
transfer, identical capture bytes, actual reset/load/cancel/edit invalidation and
joined stop accounting. Density queries are issued between polls and retained
with poll durations. This short fixture is not a performance gate or a repeat of
the original 256 m backlog workload. The existing 13 density-command checks and
42 real worker publication checks also pass with the new release library.

Both release and debug libraries were built using the pinned Zig compiler and
prebuilt godot-cpp; no SDK sources were rebuilt. The runtime probe uses release.
Two experimental headers now use relative core.h includes so the extension
build resolves them without the standalone probe's extra include path.

Normal gameplay does not call these methods. This transfers geometry only: no
normals, materials, collision publication or LOD integration is provided. Returned
Godot arrays are copies outside the native budgets. The mesher's vertex/index
limits bound each successful payload to at most 24 MB, but callers retaining
successive polls can still grow memory. Encoding also holds the world mutex;
its loaded cost and a bounded downstream consumer need qualification before use.
Thread-start failure, engine allocation failure and renderer behavior remain
unqualified. This is not a fix for runtime mining stalls or proof of 60 FPS.

Evidence: `evidence/terrain_snapshot_bridge/terrain_snapshot_bridge.json.gz`.

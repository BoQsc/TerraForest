# Opt-in native density command

Command 23 now exposes the experimental density query through TerrainCore.execute.
The existing typed bridge mutex owns world access across the call; cancellation
uses the existing per-world atomic epoch. Both debug and release extension DLLs
were rebuilt with pinned Zig and prebuilt godot-cpp (zero SDK sources rebuilt).
No terrain-backend job or player input path calls this command yet.

## Wire contract

The 36-byte request is little endian: u32 command 23, two float32 XYZ vectors
(from/to), u32 maximum cells, u32 expected build epoch. Budget must be 1..8192.
Malformed/invalid requests return the existing 12-byte envelope with status 1;
stale or cancelled requests return status 4 without a hit payload.

Successful envelopes contain a 40-byte reply: magic, command, envelope status,
world revision, query result, visited cells, float32 segment fraction, float32 XYZ
position. Query result is 0 hit, 1 miss, or 2 work-limit exhaustion. Position and
fraction are meaningful only for hits. Exhaustion is never silently a miss.
Consumers must reject stale revision/epoch results again before using them.

## Evidence

`python tools/probe_terrain_density_command.py --godot PATH` builds the release
extension and passes 13 checks on a real Godot Thread: hit, miss, bounded work,
malformed packets, invalid budgets, edited density and revision tagging, stale
epoch rejection and isolation from another TerrainCore world.
The native frozen-ray probe verifies exact wire parity for all 22 hits. The 67
numerical cases and 18 traversal controls still pass. The existing worker
publication regression also passes all 42 checks with the rebuilt release DLL.
Reports: [retained evidence](evidence/terrain_density_command).

The build fingerprint now recursively includes native headers and their relative
paths; previously it ignored nested headers such as experimental/density_ray.hpp.
This prevents a nested-header edit from silently leaving the old implementation
in a locally rebuilt DLL.

This is API integration, not gameplay adoption or performance qualification.
The command returns neither normals nor materials. Backend queue policy, stale
result consumption, arbitration against other object hits, rendered-surface
agreement and end-to-end interaction latency remain outstanding. The thread test
checks pre-existing cancellation, not a concurrently interrupted long command.
